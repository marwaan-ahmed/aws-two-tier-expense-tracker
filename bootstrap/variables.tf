variable "alert_email" {
  description = "Email address that receives the budget alerts. Set it in terraform.tfvars (gitignored)."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be an email address."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly spending limit for the budget alert, in US dollars (7 USD is about 5 GBP)."
  type        = number
  default     = 7
}
