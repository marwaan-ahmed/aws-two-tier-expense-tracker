# Long-lived resources that must survive `terraform destroy` in terraform/:
# the bucket that holds the main stack's Terraform state, and the monthly budget alert.

data "aws_caller_identity" "current" {}

# ---- Terraform state bucket -------------------------------------------------

resource "aws_s3_bucket" "state" {
  # Bucket names are global across all AWS accounts; the account ID makes it unique.
  bucket = "expense-tracker-tfstate-${data.aws_caller_identity.current.account_id}"

  # Losing this bucket means Terraform forgets everything it built.
  # To really delete it one day, remove this block first.
  lifecycle {
    prevent_destroy = true
  }
}

# Every state change keeps the previous version, so a bad apply can be undone.
# No lifecycle rule to expire old versions: each is a few KB, so keeping them
# costs next to nothing and they are the undo history.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # S3-managed keys: free, and enough for this project
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Refuse any request that isn't encrypted in transit (plain HTTP).
data "aws_iam_policy_document" "state_tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_tls_only.json
}

# ---- Budget alert -----------------------------------------------------------

# Covers the whole account, not just this project, so it also catches anything
# left running by accident. AWS budgets are in US dollars.
resource "aws_budgets_budget" "monthly" {
  name         = "expense-tracker-monthly"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Email when real spending passes 80% of the budget...
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  # ...and when AWS forecasts the month will end over budget.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
