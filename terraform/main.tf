module "network" {
  source = "./modules/network"

  name   = "${var.project}-${var.environment}"
  region = var.region

  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["eu-west-2a", "eu-west-2b"]

  public_subnet_cidrs = ["10.0.0.0/24", "10.0.1.0/24"]
  app_subnet_cidrs    = ["10.0.10.0/24", "10.0.11.0/24"]
  data_subnet_cidrs   = ["10.0.20.0/24", "10.0.21.0/24"]
}

module "loadbalancer" {
  source = "./modules/loadbalancer"

  name              = "${var.project}-${var.environment}"
  vpc_id            = module.network.vpc_id
  vpc_cidr          = module.network.vpc_cidr
  public_subnet_ids = module.network.public_subnet_ids
  allowed_ip        = var.my_ip
}

module "compute" {
  source = "./modules/compute"

  name                  = "${var.project}-${var.environment}"
  vpc_id                = module.network.vpc_id
  app_subnet_ids        = module.network.app_subnet_ids
  alb_security_group_id = module.loadbalancer.security_group_id
  target_group_arn      = module.loadbalancer.target_group_arn
}
