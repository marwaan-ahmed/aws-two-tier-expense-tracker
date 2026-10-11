# Expense tracker app

A small single-user web app for recording expenses: add an expense (amount,
category, date, optional description), list a month's expenses with
previous/next month navigation, delete an expense (with a confirm step), and see
a monthly summary (total per category, share of the month, grand total).

The footer shows **"Served by &lt;instance-id&gt; in &lt;AZ&gt;"** so you can
watch the load balancer spread requests across instances.

There is no login: the WAF only lets your IP address through.

| Stack | |
|---|---|
| Language | Python 3.9 (Amazon Linux 2023 system Python); also runs on 3.12 |
| Web | Flask + Jinja templates (server-rendered HTML, no JavaScript) |
| Database | PostgreSQL through `psycopg` 3 with plain SQL (no ORM) |
| AWS | `boto3`, only to read the database secret |
| Server | `gunicorn` under `systemd`, port 8000, no nginx (the ALB is the proxy) |

## Files

| File | Purpose |
|---|---|
| `app.py` | The whole application: config, database access, validation, routes |
| `schema.sql` | Tables, index and seed categories. The app runs it itself (idempotent) |
| `templates/` | `base.html` (layout + footer), `_month_header.html` (month title, total, month links, the two views), `expenses.html`, `summary.html`, `error.html` |
| `static/` | `style.css` (laid out like a monthly statement; light and dark mode follow the OS), `favicon.svg` |
| `requirements.txt` | Exact versions of the four libraries (plus `tzdata`) |
| `expense-app.service` | The systemd unit that runs gunicorn on the instances |

## Routes

| Route | What it does |
|---|---|
| `GET /` | Redirects to the current month |
| `GET /expenses?month=YYYY-MM` | The month's expenses, the add form and the month total |
| `POST /expenses` | Adds an expense, then redirects to that month (Post/Redirect/Get) |
| `POST /expenses/<id>/delete` | Deletes an expense, then redirects back to its month |
| `GET /summary?month=YYYY-MM` | Total per category, share of the month and grand total |
| `GET /health` | Returns `200 ok`. **Never touches the database**, so a database blip doesn't make the ASG replace healthy instances |

A missing `month` means the current month; an invalid one (e.g. `2026-13`) gets
a friendly 400 page, never a 500.

## Configuration (environment variables)

| Variable | Required | Example | Meaning |
|---|---|---|---|
| `DB_HOST` | yes | `expense-tracker-dev.xxxx.eu-west-2.rds.amazonaws.com` | Database host name (the RDS endpoint address, without the port) |
| `DB_PORT` | no (`5432`) | `5432` | Database port |
| `DB_NAME` | yes | `expenses` | Database name (the RDS `db_name`) |
| `DB_SECRET_ARN` | on AWS | `arn:aws:secretsmanager:eu-west-2:…:secret:rds!db-…` | The RDS-managed secret with `username` and `password` |
| `AWS_REGION` | on AWS | `eu-west-2` | Region used for the Secrets Manager call |
| `DB_USER` / `DB_PASSWORD` | local only | `postgres` / `…` | Used **only** when `DB_SECRET_ARN` is not set |
| `DB_SSLMODE` | no (`require`) | `disable` | Local only, for a database without TLS. Leave unset on AWS |

If `DB_HOST`, `DB_NAME`, or both `DB_SECRET_ARN` and `DB_USER`, are missing,
the app refuses to start and the error tells you which one. A wrong
configuration fails straight away. It doesn't half-work.

## Run it locally

You need Python 3.9+ and a PostgreSQL server you can reach (for example
Postgres.app, or `brew install postgresql@16`). Create an empty database. The
app creates its own tables on first use:

```bash
createdb expenses
```

Create a virtual environment **outside** `app/`, so the Terraform zip of
`app/` doesn't pick it up:

```bash
python3 -m venv ~/.venvs/expense-app
~/.venvs/expense-app/bin/pip install -r requirements.txt
```

Set the configuration and start gunicorn from inside `app/`:

```bash
export DB_HOST=localhost DB_PORT=5432 DB_NAME=expenses
export DB_USER="$USER" DB_PASSWORD=""        # whatever your local PostgreSQL uses
export DB_SSLMODE=disable                    # local PostgreSQL usually has no TLS

~/.venvs/expense-app/bin/gunicorn --bind 127.0.0.1:8000 --workers 2 app:app
```

Open <http://127.0.0.1:8000>. The footer says "Served by &lt;your computer's
name&gt; (not on EC2)", because there is no EC2 metadata service on a laptop.
For automatic reloading while editing, use
`~/.venvs/expense-app/bin/flask --app app run --debug` instead.

## Deployment contract (what the Phase 3 `user_data` must provide)

| Item | Value |
|---|---|
| App code | `/opt/expense-app/` (with `app.py` at its root), owned by root, read-only for the app |
| Virtualenv | `/opt/expense-app/venv` (`python3 -m venv`, then `pip install -r requirements.txt`) |
| System user | `expense-app`, no login shell, no home directory |
| Environment file | `/etc/sysconfig/expense-app`, `root:root`, mode `0600` (systemd reads it as root) |
| systemd unit | `expense-app.service` → `/etc/systemd/system/expense-app.service`, then `systemctl enable --now expense-app` |
| Port | `8000` on all interfaces (the app security group only allows the ALB) |
| Health check | `GET /health` → `200`, body `ok` |
| Log file | `/var/log/expense-app.log` (JSON lines, one per request; created by systemd as root, mode 0644) |
| IAM (instance role) | `secretsmanager:GetSecretValue` on **that one secret ARN**. No KMS permission needed while the secret uses the default `aws/secretsmanager` key (the RDS default) |

A sketch of the steps (Phase 3 writes the real script):

```bash
useradd --system --no-create-home --shell /sbin/nologin expense-app
mkdir -p /opt/expense-app && unzip -o /tmp/app.zip -d /opt/expense-app
python3 -m venv /opt/expense-app/venv
/opt/expense-app/venv/bin/pip install -r /opt/expense-app/requirements.txt   # via the NAT gateway to PyPI

cat > /etc/sysconfig/expense-app <<EOF
DB_HOST=<rds address>
DB_PORT=5432
DB_NAME=<db name>
DB_SECRET_ARN=<rds master user secret arn>
AWS_REGION=eu-west-2
EOF
chmod 600 /etc/sysconfig/expense-app

cp /opt/expense-app/expense-app.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now expense-app
```

### Logs → CloudWatch

systemd appends the app's stdout and stderr to `/var/log/expense-app.log`,
because the CloudWatch agent reads **files**, not the systemd journal. App lines
are JSON. gunicorn's own start/stop lines are plain text. The CloudWatch agent
config needs an entry like this. The agent runs as root unless its config sets
`run_as_user`, so it can read the file:

```json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/expense-app.log",
            "log_group_name": "/expense-tracker-dev/app",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
```

The file only grows, so also install a logrotate rule. Use `copytruncate`,
because systemd keeps the file open:

```
/var/log/expense-app.log {
    daily
    rotate 3
    maxsize 50M
    missingok
    notifempty
    compress
    copytruncate
}
```

### Graceful shutdown (ASG instance refresh)

On stop, systemd sends `SIGTERM` to gunicorn, which stops taking new requests
and lets in-flight ones finish (up to 30 s). Before that, the ALB stops sending
new requests while the target deregisters, so a short target group
`deregistration_delay` (e.g. 30 s instead of the 300 s default) keeps refreshes
quick.

## Design notes

The reasoning behind each of these is in comments next to the code in `app.py`.

- **Money** is `NUMERIC(10,2)` in PostgreSQL and `Decimal` in Python, never float.
  Amounts must look like `12`, `12.5` or `12.50`, be more than £0 and fit the column.
- **One database connection per request**, so it can never be stale after an RDS
  reboot, failover or password rotation.
- **The secret is cached**, and re-read once if PostgreSQL rejects the password.
- **Schema setup** runs on each worker's first database request, under an advisory
  lock, so the app starts (and `/health` answers) even while the database is down.
- **Cross-site form protection** without sessions: a POST is accepted only if the
  browser's `Origin` header is this site.
- **No Flask sessions**, because they would need the same secret key on every instance.
- **Logging:** one JSON line per request. ALB health checks are not logged.

## Python version note

AL2023's system Python is 3.9, which reached upstream end of life in October
2025. The pinned versions are the newest that still support 3.9 **and** have
arm64 wheels for 3.12. boto3 has stopped supporting 3.9 (it logs a
deprecation warning at start-up), so `1.42.x` is its last 3.9 line. AL2023
also offers newer Pythons as packages (e.g. `python3.12`). Moving the venv to it later only means
changing `python3` to `python3.12` in `user_data` and bumping the pins.
