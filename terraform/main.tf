# The whole stack. Each module is one part of the architecture.

module "network" {
  source = "./modules/network"

  name   = "${var.project}-${var.environment}"
  region = var.region

  # Both zones must be in var.region.
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["eu-west-2a", "eu-west-2b"]

  public_subnet_cidrs = ["10.0.0.0/24", "10.0.1.0/24"]
  app_subnet_cidrs    = ["10.0.10.0/24", "10.0.11.0/24"]
  data_subnet_cidrs   = ["10.0.20.0/24", "10.0.21.0/24"]
}
