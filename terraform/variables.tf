# Settings used in more than one place: resource names, the tags on every
# resource (providers.tf) and the module calls (main.tf). The network's address
# ranges are used once, so they're written out in main.tf.

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
