variable "name" {
  description = "Start of every resource name, for example expense-tracker-dev."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to build in."
  type        = string
}

variable "vpc_cidr" {
  description = "The VPC's address range. The load balancer may only send traffic inside it."
  type        = string
}

variable "public_subnet_ids" {
  description = "The two public subnets the load balancer sits in."
  type        = list(string)
}

variable "allowed_ip" {
  description = "The only IP address the WAF lets in, for example 203.0.113.10/32."
  type        = string
}
