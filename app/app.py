"""Expense tracker: a small Flask app for the AWS two-tier portfolio project.

It runs under gunicorn (sync workers) behind an Application Load Balancer and
stores data in PostgreSQL. README.md explains the configuration and the
contract with the infrastructure (port, health check, log file, IAM).

Runs on Python 3.9 (Amazon Linux 2023 system Python) and 3.12.
"""

import json
import logging
import os
import re
import socket
import sys
import time
import urllib.request
from datetime import date, datetime, timezone
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path
from zoneinfo import ZoneInfo

import boto3
import psycopg
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from flask import Flask, abort, g, redirect, render_template, request, url_for
from psycopg.rows import dict_row
from werkzeug.exceptions import HTTPException, InternalServerError
from werkzeug.middleware.proxy_fix import ProxyFix

# --------------------------------------------------------------------------
# Logging: one JSON object per line on stdout.
# systemd appends stdout to a file and the CloudWatch agent ships that file.
# JSON lets CloudWatch Logs Insights filter on fields (e.g. status >= 500).
# --------------------------------------------------------------------------


class JsonFormatter(logging.Formatter):
    def format(self, record):
        entry = {
            "time": datetime.fromtimestamp(record.created, timezone.utc).isoformat(
                timespec="milliseconds"
            ),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        # Structured fields are passed as log.info("...", extra={"fields": {...}}).
        entry.update(getattr(record, "fields", {}))
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, default=str)


def _configure_logging():
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(logging.INFO)
    # Library warnings (e.g. deprecation notices) become JSON lines too,
    # instead of stray plain-text lines on stderr.
    logging.captureWarnings(True)


_configure_logging()
log = logging.getLogger("expense-app")

# --------------------------------------------------------------------------
# Configuration: environment variables only, so the same code runs on EC2
# today and in a container (v2) later.
# --------------------------------------------------------------------------


def _require_env(name):
    value = os.environ.get(name, "").strip()
    if not value:
        # Failing at start-up makes a misconfigured instance obviously broken,
        # instead of half-working.
        raise RuntimeError(f"Missing required environment variable {name} (see README.md)")
    return value


DB_HOST = _require_env("DB_HOST")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = _require_env("DB_NAME")
DB_SECRET_ARN = os.environ.get("DB_SECRET_ARN", "").strip() or None
AWS_REGION = os.environ.get("AWS_REGION", "").strip() or None
# "require" = always encrypt. Only override it for a local database without TLS.
DB_SSLMODE = os.environ.get("DB_SSLMODE", "require")
# Decides what "today" and "this month" mean (the servers run on UTC).
APP_TZ = ZoneInfo("Europe/London")

# Local development only: without a secret ARN, credentials come from env vars.
DB_USER = os.environ.get("DB_USER", "")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
if not DB_SECRET_ARN and not DB_USER:
    raise RuntimeError("Set DB_SECRET_ARN (on AWS) or DB_USER/DB_PASSWORD (locally); see README.md")

SCHEMA_SQL = Path(__file__).with_name("schema.sql").read_text(encoding="utf-8")

MAX_DESCRIPTION = 200  # matches VARCHAR(200)
# A sanity range for dates. It also catches typos like 0224 or 20244.
MIN_DATE = date(1900, 1, 1)
MAX_DATE = date(2999, 12, 31)

# [0-9] rather than \d: in Python \d also matches non-ASCII digits like "٣".
MONTH_RE = re.compile(r"[0-9]{4}-[0-9]{2}")
DATE_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")
# 12, 12.5 or 12.50. At most 8 digits before the point, so it always fits
# NUMERIC(10, 2). Rejects NaN, Infinity, 1e5, -3 and 1.234 without extra checks.
AMOUNT_RE = re.compile(r"[0-9]{1,8}(\.[0-9]{1,2})?")

log.info(
    "app starting",
    extra={
        "fields": {
            "db_host": DB_HOST,
            "db_port": DB_PORT,
            "db_name": DB_NAME,
            "db_sslmode": DB_SSLMODE,
            "db_credentials": "secrets-manager" if DB_SECRET_ARN else "environment",
            "timezone": str(APP_TZ),
            "python": sys.version.split()[0],
        }
    },
)

# --------------------------------------------------------------------------
# Instance identity for the footer ("Served by i-... in eu-west-2a").
# Fetched once per worker from the EC2 Instance Metadata Service (IMDSv2:
# first get a session token with PUT, then send it with each GET).
# --------------------------------------------------------------------------

IMDS_URL = "http://169.254.169.254/latest"
_identity = None


def _fetch_identity():
    token_request = urllib.request.Request(
        f"{IMDS_URL}/api/token",
        method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
    )
    with urllib.request.urlopen(token_request, timeout=1) as response:
        token = response.read().decode()

    def get(path):
        req = urllib.request.Request(
            f"{IMDS_URL}/meta-data/{path}", headers={"X-aws-ec2-metadata-token": token}
        )
        with urllib.request.urlopen(req, timeout=1) as response:
            return response.read().decode()

    return {"instance_id": get("instance-id"), "az": get("placement/availability-zone")}


def instance_identity():
    global _identity
    if _identity is None:
        try:
            _identity = _fetch_identity()
        except Exception:  # the footer is cosmetic; never fail a request for it
            # Not on EC2 (e.g. a laptop). The result is cached, so the 1 s
            # timeout is paid once per worker, not on every request.
            _identity = {"instance_id": socket.gethostname() or "local", "az": None}
            log.info("instance metadata unavailable; assuming not on EC2")
    return _identity


# --------------------------------------------------------------------------
# Database credentials: the RDS-managed secret in Secrets Manager.
# Cached in memory; re-fetched when the database rejects the password
# (RDS rotates the managed secret every 7 days by default).
# --------------------------------------------------------------------------

_secrets_client = None
_credentials = None


def db_credentials(refresh=False):
    global _secrets_client, _credentials
    if not DB_SECRET_ARN:
        return DB_USER, DB_PASSWORD
    if _credentials is None or refresh:
        if _secrets_client is None:
            _secrets_client = boto3.client(
                "secretsmanager",
                region_name=AWS_REGION,
                # Short timeouts: a slow AWS API must not hang a worker.
                config=Config(connect_timeout=3, read_timeout=5, retries={"max_attempts": 3}),
            )
        response = _secrets_client.get_secret_value(SecretId=DB_SECRET_ARN)
        secret = json.loads(response["SecretString"])
        _credentials = (secret["username"], secret["password"])
        log.info("database credentials loaded from Secrets Manager")  # never log the values
    return _credentials


# --------------------------------------------------------------------------
# Database connections.
#
# One connection per request: opened on first use, closed when the request
# ends. Why: with gunicorn sync workers each worker handles one request at a
# time, so a pool buys little, and a fresh connection can never be a stale one
# (after an RDS reboot, failover or password rotation). The cost is a few
# milliseconds of connection setup per request, which this app can afford.
# At most (workers x instances) connections exist, far below RDS's limit.
# --------------------------------------------------------------------------

# Any fixed 64-bit number works; what matters is that every worker on every
# instance uses the same one.
SCHEMA_LOCK_ID = 53_012_026
_schema_ready = False


def _open_connection(user, password):
    return psycopg.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=user,
        password=password,
        sslmode=DB_SSLMODE,
        # Without this, an unreachable database blocks the worker for minutes.
        connect_timeout=5,
        application_name="expense-app",
        autocommit=True,  # each statement commits itself; multi-step work uses conn.transaction()
        row_factory=dict_row,
    )


def _connect():
    user, password = db_credentials()
    try:
        return _open_connection(user, password)
    except psycopg.OperationalError as exc:
        # psycopg sets no error code on a failed connection, so match the
        # server's message (tested against a real PostgreSQL).
        if not (DB_SECRET_ARN and "password authentication failed" in str(exc)):
            raise
        # The password was probably rotated: fetch the secret again, retry once.
        log.warning("database rejected the cached password; re-fetching the secret")
        user, password = db_credentials(refresh=True)
        return _open_connection(user, password)


def ensure_schema(conn):
    """Create tables and seed categories once per worker, on first DB use.

    Doing this lazily (not at import) means the app starts and /health answers
    even while the database is unreachable; if it fails, the next request tries
    again.
    """
    global _schema_ready
    if _schema_ready:
        return
    # Several workers on several instances start together. Running CREATE TABLE
    # concurrently can fail even with IF NOT EXISTS, so they queue on a
    # PostgreSQL advisory lock. The "xact" lock is released automatically when
    # the transaction ends, even if something fails.
    with conn.transaction():
        conn.execute("SELECT pg_advisory_xact_lock(%s)", (SCHEMA_LOCK_ID,))
        conn.execute(SCHEMA_SQL)  # no parameters, so several statements are allowed
    _schema_ready = True
    log.info("database schema ready")


def get_db():
    if "db" not in g:
        g.db = _connect()
        ensure_schema(g.db)
    return g.db


# --------------------------------------------------------------------------
# Dates, months and money
# --------------------------------------------------------------------------


def today():
    return datetime.now(APP_TZ).date()


def month_key(d):
    return f"{d.year:04d}-{d.month:02d}"


def add_months(first_of_month, n):
    year, month_index = divmod(first_of_month.year * 12 + first_of_month.month - 1 + n, 12)
    return date(year, month_index + 1, 1)


def parse_month(value):
    """'2026-09' -> date(2026, 9, 1); anything else -> None."""
    if not MONTH_RE.fullmatch(value):
        return None
    year, month = int(value[:4]), int(value[5:])
    if not (MIN_DATE.year <= year <= MAX_DATE.year and 1 <= month <= 12):
        return None
    return date(year, month, 1)


def month_from_query():
    raw = request.args.get("month", "")
    if not raw:
        return today().replace(day=1)
    month = parse_month(raw)
    if month is None:
        abort(400, description="The month must look like 2026-09 (year-month).")
    return month


def month_from_form():
    # A hidden field in the add form: which month to show again if the input
    # needs fixing. A bad value just falls back to the current month.
    return parse_month(request.form.get("month", "")) or today().replace(day=1)


def month_context(month):
    """Values every month page needs: labels and prev/next links."""
    prev_month, next_month = add_months(month, -1), add_months(month, 1)
    return {
        "month": month,
        "month_key": month_key(month),
        "prev_month": prev_month if prev_month >= MIN_DATE else None,
        "next_month": next_month if next_month <= MAX_DATE else None,
        "is_current_month": month == today().replace(day=1),
    }


def parse_amount(raw):
    """Return (Decimal, None) or (None, error message). Never uses float."""
    text = raw.strip()
    if not AMOUNT_RE.fullmatch(text):
        return None, "Enter an amount like 12.50."
    amount = Decimal(text)
    if amount <= 0:
        return None, "Must be more than £0."
    return amount, None


def parse_expense_date(raw):
    text = raw.strip()
    if not text:
        return today(), None  # the spec: date defaults to today
    if DATE_RE.fullmatch(text):
        try:
            value = date.fromisoformat(text)
        except ValueError:  # e.g. 2026-02-30
            value = None
        if value is not None and MIN_DATE <= value <= MAX_DATE:
            return value, None
    return None, "Enter a real date."


def validate_expense(form, category_ids):
    """Return (values, errors). errors maps field name -> message."""
    errors = {}
    amount, error = parse_amount(form["amount"])
    if error:
        errors["amount"] = error

    try:
        category_id = int(form["category_id"])
    except ValueError:
        category_id = None
    if category_id not in category_ids:
        errors["category_id"] = "Choose a category."

    spent_on, error = parse_expense_date(form["spent_on"])
    if error:
        errors["spent_on"] = error

    # PostgreSQL text cannot store the NUL character, so drop it.
    description = form["description"].replace("\x00", "").strip()
    if len(description) > MAX_DESCRIPTION:
        errors["description"] = f"Too long ({MAX_DESCRIPTION} characters at most)."

    values = {
        "amount": amount,
        "category_id": category_id,
        "spent_on": spent_on,
        "description": description,
    }
    return values, errors


# --------------------------------------------------------------------------
# Flask app
# --------------------------------------------------------------------------

app = Flask(__name__)
# The ALB is exactly one proxy in front of us. Trust one hop of X-Forwarded-For
# (real client IP for logs) and X-Forwarded-Proto (http now, https from Phase 6).
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1)
app.config["MAX_CONTENT_LENGTH"] = 16 * 1024  # our forms are tiny; reject huge bodies early

CSP = (
    "default-src 'self'; script-src 'none'; object-src 'none'; base-uri 'none'; "
    "form-action 'self'; frame-ancestors 'none'"
)


@app.template_filter("gbp")
def format_gbp(value):
    return f"£{value:,.2f}"


@app.template_filter("month_label")
def format_month_label(d):
    return d.strftime("%B %Y")


@app.template_filter("short_date")
def format_short_date(d):
    return f"{d:%a} {d.day} {d:%b}"


@app.context_processor
def template_globals():
    # Must never touch the database: error pages use it too.
    return {"served_by": instance_identity(), "current_month_key": month_key(today())}


def is_cross_site_request():
    """Stateless CSRF defence for a login-less app.

    There is no login, but the WAF allows my IP, so a malicious page open in my
    browser could still submit a form to this app. Every current browser sends
    an Origin header on a form POST saying which site the form came from, so
    accept POSTs only when it is this site. No Origin at all means a tool like
    curl, not a web page, so it cannot be a cross-site forgery.
    """
    origin = request.headers.get("Origin")
    if origin is None:
        return False
    # "null" (a hidden origin) never matches, so it is rejected too.
    return origin.lower() != f"{request.scheme}://{request.host}".lower()


@app.before_request
def before_request():
    g.start = time.perf_counter()
    if request.method == "POST" and is_cross_site_request():
        log.warning(
            "blocked cross-site POST",
            extra={"fields": {"path": request.path, "origin": request.headers.get("Origin")}},
        )
        abort(403, description="This form was sent from another website, so it was blocked.")


@app.after_request
def after_request(response):
    response.headers["Content-Security-Policy"] = CSP
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "same-origin"

    # The ALB checks /health every few seconds from each of its nodes. Logging
    # those would bury real requests (and cost log storage); the ALB's
    # HealthyHostCount metric already records them.
    if request.path != "/health":
        fields = {
            "method": request.method,
            "path": request.path,
            "status": response.status_code,
            "duration_ms": round((time.perf_counter() - g.start) * 1000, 1),
            "client_ip": request.remote_addr,
            "instance_id": instance_identity()["instance_id"],
        }
        log.info("request", extra={"fields": fields})
    return response


@app.teardown_appcontext
def close_db(exc):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()


# ---- Error pages: friendly HTML, never a stack trace -----------------------


def error_page(code, title, message, headers=None):
    body = render_template("error.html", code=code, title=title, message=message)
    return body, code, headers or {}


# code: (title, message). A message of None keeps the one passed to abort();
# the others replace Flask's built-in wording.
HTTP_ERRORS = {
    400: ("Bad request", None),
    403: ("Blocked", None),
    404: ("Page not found", "There's nothing at this address."),
    405: ("Not allowed", "That action isn't available here."),
    413: ("Too much data", "That form sent far more data than it should."),
}


@app.errorhandler(HTTPException)
def http_error(exc):
    title, message = HTTP_ERRORS.get(exc.code, (exc.name, None))
    # get_headers() keeps e.g. the "Allow" header on a 405.
    return error_page(exc.code, title, message or exc.description, dict(exc.get_headers()))


@app.errorhandler(psycopg.OperationalError)
@app.errorhandler(BotoCoreError)
@app.errorhandler(ClientError)
def database_unavailable(exc):
    # 503 = "temporarily unavailable". Only this request fails; /health stays
    # 200, so the ALB keeps the instance and it recovers when the DB is back.
    # The error message says what went wrong (timeout, refused, access denied);
    # a stack trace per request during an outage would only add noise.
    log.error(
        "database unavailable",
        extra={"fields": {"error_type": type(exc).__name__, "error": str(exc), "path": request.path}},
    )
    return error_page(
        503,
        "Can't reach the database",
        "The database isn't responding. Try again in a minute.",
    )


@app.errorhandler(InternalServerError)
def internal_error(exc):
    # Flask has already logged the exception with its traceback.
    return error_page(
        500, "Something went wrong", "Try again. If it keeps happening, the app log has the details."
    )


# ---- Routes -----------------------------------------------------------------


@app.get("/health")
def health():
    # Deliberately does NOT touch the database: a database blip must not make
    # the ALB/ASG replace instances that are otherwise fine.
    return "ok", 200, {"Content-Type": "text/plain; charset=utf-8"}


@app.get("/")
def index():
    return redirect(url_for("list_expenses", month=month_key(today())))


def load_categories(conn):
    return conn.execute("SELECT id, name FROM categories ORDER BY id").fetchall()


def render_expenses(month, form=None, errors=None, status=200):
    conn = get_db()
    # Half-open range [1st of month, 1st of next month) uses the spent_on index.
    expenses = conn.execute(
        """
        SELECT e.id, e.amount, e.description, e.spent_on, c.name AS category
          FROM expenses e
          JOIN categories c ON c.id = e.category_id
         WHERE e.spent_on >= %s AND e.spent_on < %s
         ORDER BY e.spent_on DESC, e.id DESC
        """,
        (month, add_months(month, 1)),
    ).fetchall()

    if form is None:
        form = {"amount": "", "category_id": "", "spent_on": today().isoformat(), "description": ""}

    return (
        render_template(
            "expenses.html",
            expenses=expenses,
            total=sum((e["amount"] for e in expenses), Decimal("0")),
            expense_count=len(expenses),
            categories=load_categories(conn),
            form=form,
            errors=errors or {},
            min_date=MIN_DATE.isoformat(),
            max_date=MAX_DATE.isoformat(),
            **month_context(month),
        ),
        status,
    )


@app.get("/expenses")
def list_expenses():
    return render_expenses(month_from_query())


@app.post("/expenses")
def add_expense():
    form = {
        name: request.form.get(name, "")
        for name in ("amount", "category_id", "spent_on", "description")
    }
    conn = get_db()
    category_ids = {c["id"] for c in load_categories(conn)}
    values, errors = validate_expense(form, category_ids)
    if errors:
        # Show the same page again with the messages and what the user typed.
        return render_expenses(month_from_form(), form=form, errors=errors, status=400)

    conn.execute(
        "INSERT INTO expenses (amount, category_id, description, spent_on) VALUES (%s, %s, %s, %s)",
        (values["amount"], values["category_id"], values["description"], values["spent_on"]),
    )
    # Post/Redirect/Get: refreshing the page afterwards won't add it twice.
    # Go to the month of the expense's date, which may differ from the page.
    return redirect(url_for("list_expenses", month=month_key(values["spent_on"])), code=303)


@app.post("/expenses/<int:expense_id>/delete")
def delete_expense(expense_id):
    row = get_db().execute(
        "DELETE FROM expenses WHERE id = %s RETURNING spent_on", (expense_id,)
    ).fetchone()
    if row is None:
        # Already gone (e.g. a double click, or deleted in another tab).
        return redirect(url_for("index"), code=303)
    return redirect(url_for("list_expenses", month=month_key(row["spent_on"])), code=303)


@app.get("/summary")
def summary():
    month = month_from_query()
    rows = get_db().execute(
        """
        SELECT c.name AS category, COUNT(*) AS count, SUM(e.amount) AS total
          FROM expenses e
          JOIN categories c ON c.id = e.category_id
         WHERE e.spent_on >= %s AND e.spent_on < %s
         GROUP BY c.id, c.name
         ORDER BY total DESC, c.name
        """,
        (month, add_months(month, 1)),
    ).fetchall()
    total = sum((r["total"] for r in rows), Decimal("0"))
    for r in rows:
        r["percent"] = (r["total"] * 100 / total).quantize(Decimal("0.1"), ROUND_HALF_UP)
    return render_template(
        "summary.html",
        rows=rows,
        total=total,
        expense_count=sum(r["count"] for r in rows),
        **month_context(month),
    )
