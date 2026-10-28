variable "name" {
  description = "Start of every resource name, for example expense-tracker-dev."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to build in."
  type        = string
}

variable "data_subnet_ids" {
  description = "The two data subnets the database sits in."
  type        = list(string)
}

variable "app_security_group_id" {
  description = "The app servers' security group. Only it can reach the database."
  type        = string
}

variable "multi_az" {
  description = "Keep a standby copy of the database in the other zone. Doubles the database cost."
  type        = bool
}
