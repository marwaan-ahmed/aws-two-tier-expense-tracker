# AWS Two-Tier Expense Tracker (Terraform)

A portfolio project: an expense tracker web app on a two-tier AWS architecture
(ALB + WAF → EC2 Auto Scaling group in private subnets → RDS PostgreSQL), built entirely with Terraform.

> Work in progress — built phase by phase.

## Repository layout

| Path | Purpose |
|---|---|
| `bootstrap/` | Long-lived resources (state bucket, budget alert). Applied once, never destroyed |
| `terraform/` | Main stack (root module). Applied and destroyed each session |
| `terraform/modules/` | Components used by the main stack: `network`, `loadbalancer`, `compute`, `database`, `monitoring` |
| `app/` | The expense tracker application (Python/Flask) |
| `.github/workflows/` | CI/CD (Phase 5) |

## Monitoring

Six CloudWatch alarms email me through SNS when something goes wrong, and again when it recovers. They
watch symptoms a user would notice first (errors, slowness, servers down), then the database. There's one
dashboard with the same metrics (`terraform output dashboard_url`).

After the first apply, AWS sends a "subscription confirmation" email. Alerts only arrive once the link in
it has been clicked. The topic is rebuilt with the stack, so this happens once per session.

### SLO

Over any 30 days:

- 99% of requests succeed (no 5xx from the app or the load balancer)
- 95% of requests are answered in under 0.5 seconds

### Runbooks

**Unhealthy hosts** (`*-unhealthy-hosts`)
- Means: a server stopped answering `/health`. The other server keeps the site up.
- Check: EC2 → Target groups → targets tab. Then the app's log stream for that server in CloudWatch
  (`/expense-tracker-dev/app`).
- Fix: usually nothing. The Auto Scaling group replaces the server within a few minutes and the OK email
  follows. If new servers keep failing, open a session on one through SSM and run
  `sudo systemctl status expense-app` and `sudo tail -50 /var/log/cloud-init-output.log`.

**5xx errors** (`*-5xx-errors`)
- Means: the app returned server errors.
- Check: search the app logs for `"level": "ERROR"`. A 503 with "database unavailable" points at the
  database; anything else is an app bug.
- Fix: if it's the database, see the database alarms below and check it's `available` in RDS. If it's
  the app, fix the code and `terraform apply`. The instance refresh rolls it out.

**Slow responses** (`*-slow-responses`)
- Means: the slowest 5% of requests took longer than 0.5 seconds.
- Check: the dashboard. Is database CPU high? Are fewer servers running than usual?
- Fix: if CPU on the servers is high, the Auto Scaling group adds servers on its own (target 50%). If
  the database is the bottleneck, see the database CPU runbook.

**Database CPU** (`*-db-cpu`)
- Means: the database has been over 80% CPU for 10 minutes.
- Check: RDS → the database → Monitoring. Look for a spike in connections or requests at the same time.
- Fix: find what's sending the load. If it's real traffic, move to a bigger instance class
  (`db.t4g.small`).

**Database storage** (`*-db-storage`)
- Means: less than 2 GB of the 20 GB disk is free.
- Check: RDS → the database → Monitoring → free storage space, and how fast it's falling.
- Fix: raise `allocated_storage` in `modules/database` and apply. RDS grows the disk without downtime.

**Database connections** (`*-db-connections`)
- Means: more than 50 connections are open. Normal is a handful (2 servers × 3 workers).
- Check: are there more servers than usual? Is the app opening connections without closing them?
- Fix: restart the app on the affected servers, or let the Auto Scaling group replace them, then look for
  the leak in the code.
