variable "name" {
  description = "Start of every resource name, for example expense-tracker-dev."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to build in."
  type        = string
}

variable "app_subnet_ids" {
  description = "The two app subnets the servers run in."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "The load balancer's security group. Only it can reach the servers."
  type        = string
}

variable "target_group_arn" {
  description = "The load balancer target group the servers register with."
  type        = string
}

variable "vpc_cidr" {
  description = "The VPC's address range. The servers may only reach the database inside it."
  type        = string
}

variable "region" {
  description = "AWS region, for example eu-west-2. The app uses it to read the database secret."
  type        = string
}

variable "app_dir" {
  description = "Path to the app's source folder. It's zipped and uploaded to S3 for the servers."
  type        = string
}

variable "db_host" {
  description = "The database's address."
  type        = string
}

variable "db_name" {
  description = "The database's name."
  type        = string
}

variable "db_secret_arn" {
  description = "The Secrets Manager secret holding the database username and password."
  type        = string
}
