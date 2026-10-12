variable "name" {
  description = "Start of every resource name. For example, expense-tracker-dev gives expense-tracker-dev-vpc."
  type        = string
}

variable "region" {
  description = "AWS region the network is in, for example eu-west-2. The S3 endpoint's service name includes it."
  type        = string
}

variable "vpc_cidr" {
  description = "Address range for the whole VPC, for example 10.0.0.0/16. Every subnet's range must fit inside it."
  type        = string
}

variable "availability_zones" {
  description = "The two availability zones to use: zone a first, then zone b."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Address ranges for the two public subnets: zone a first, then zone b."
  type        = list(string)
}

variable "app_subnet_cidrs" {
  description = "Address ranges for the two app subnets: zone a first, then zone b."
  type        = list(string)
}

variable "data_subnet_cidrs" {
  description = "Address ranges for the two data subnets: zone a first, then zone b."
  type        = list(string)
}
