variable "name" {
  description = "Start of every resource name, for example expense-tracker-dev."
  type        = string
}

variable "region" {
  description = "AWS region, for example eu-west-2. The dashboard's graphs need it."
  type        = string
}

variable "alert_email" {
  description = "Email address that receives alarm and recovery emails."
  type        = string
}

variable "load_balancer_arn_suffix" {
  description = "The load balancer's ID as CloudWatch knows it (the end of its ARN)."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "The target group's ID as CloudWatch knows it (the end of its ARN)."
  type        = string
}

variable "asg_name" {
  description = "The Auto Scaling group's name."
  type        = string
}

variable "db_instance_id" {
  description = "The database's identifier."
  type        = string
}
