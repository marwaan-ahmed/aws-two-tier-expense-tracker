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
