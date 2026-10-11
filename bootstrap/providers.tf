terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # No backend block on purpose: this stack creates the bucket that terraform/ keeps
  # its state in, so its own state can't live there. It stays in a local
  # terraform.tfstate here (gitignored). It's small and rarely changes; if it is
  # ever lost, `terraform import` reconnects the bucket and budget.
}

provider "aws" {
  region = "eu-west-2"

  default_tags {
    tags = {
      Project     = "expense-tracker"
      Environment = "shared" # used by every environment, not just dev
      ManagedBy   = "Terraform"
    }
  }
}
