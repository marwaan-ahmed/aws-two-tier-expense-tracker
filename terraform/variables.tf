variable "project" {
  description = "Project name, used in resource names and the Project tag."
  type        = string
  default     = "expense-tracker"
}

variable "environment" {
  description = "Environment name, used in resource names and the Environment tag."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region to build in."
  type        = string
  default     = "eu-west-2"
}

variable "my_ip" {
  description = "Your public IP address with /32 on the end, for example 203.0.113.10/32. Only this address gets past the WAF."
  type        = string
}

variable "alert_email" {
  description = "Email address for alarm and recovery emails. Set it in terraform.tfvars."
  type        = string
}
