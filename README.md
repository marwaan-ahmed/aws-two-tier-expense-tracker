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
