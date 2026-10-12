# The network: one VPC across two availability zones (a and b), with three
# kinds of subnet in each zone:
#   public - the load balancer and the NAT gateway; can reach the internet
#   app    - the web servers; can reach out to the internet only through the NAT gateway
#   data   - the database; no internet access at all
#
# Names, address ranges and zones come in as variables (see variables.tf).

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-vpc"
  }
}

# Every VPC comes with a default security group that lets everything inside it
# talk to everything else. Declaring it with no rules empties it, so nothing
# can use it by accident.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-igw"
  }
}

# ---- Subnets ----
# In each list variable, [0] is zone a and [1] is zone b.

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[0]
  availability_zone = var.availability_zones[0]

  tags = {
    Name = "${var.name}-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[1]
  availability_zone = var.availability_zones[1]

  tags = {
    Name = "${var.name}-public-b"
  }
}

resource "aws_subnet" "app_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.app_subnet_cidrs[0]
  availability_zone = var.availability_zones[0]

  tags = {
    Name = "${var.name}-app-a"
  }
}

resource "aws_subnet" "app_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.app_subnet_cidrs[1]
  availability_zone = var.availability_zones[1]

  tags = {
    Name = "${var.name}-app-b"
  }
}

resource "aws_subnet" "data_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.data_subnet_cidrs[0]
  availability_zone = var.availability_zones[0]

  tags = {
    Name = "${var.name}-data-a"
  }
}

resource "aws_subnet" "data_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.data_subnet_cidrs[1]
  availability_zone = var.availability_zones[1]

  tags = {
    Name = "${var.name}-data-b"
  }
}

# ---- NAT gateway: lets the app subnets reach out without being reachable ----

# The NAT gateway needs its own public IP address.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.name}-nat"
  }
}

# One NAT gateway, in zone a, to keep the cost down. If zone a goes down, the
# app servers in zone b lose outbound access only; the site stays up.
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id

  tags = {
    Name = "${var.name}-nat"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.main]
}

# ---- Route tables: where each subnet's traffic is allowed to go ----

# Public subnets: anything outside the VPC goes through the internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.name}-public"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# App subnets: anything outside the VPC goes through the NAT gateway.
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.name}-app"
  }
}

resource "aws_route_table_association" "app_a" {
  subnet_id      = aws_subnet.app_a.id
  route_table_id = aws_route_table.app.id
}

resource "aws_route_table_association" "app_b" {
  subnet_id      = aws_subnet.app_b.id
  route_table_id = aws_route_table.app.id
}

# Data subnets: no routes at all, so the database can only talk to other
# subnets inside the VPC.
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-data"
  }
}

resource "aws_route_table_association" "data_a" {
  subnet_id      = aws_subnet.data_a.id
  route_table_id = aws_route_table.data.id
}

resource "aws_route_table_association" "data_b" {
  subnet_id      = aws_subnet.data_b.id
  route_table_id = aws_route_table.data.id
}

# ---- S3 endpoint ----

# A free, private route to S3 for the app subnets. Amazon Linux updates and the
# app's code are downloaded from S3, so they skip the NAT gateway.
resource "aws_vpc_endpoint" "s3" {
  vpc_id          = aws_vpc.main.id
  service_name    = "com.amazonaws.${var.region}.s3"
  route_table_ids = [aws_route_table.app.id]

  tags = {
    Name = "${var.name}-s3"
  }
}
