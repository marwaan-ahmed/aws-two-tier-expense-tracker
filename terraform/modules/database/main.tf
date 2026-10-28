# Subnet group

resource "aws_db_subnet_group" "main" {
  name       = "${var.name}-db"
  subnet_ids = var.data_subnet_ids

  tags = {
    Name = "${var.name}-db"
  }
}

# Security group

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Database: PostgreSQL from the app servers only"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-db"
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = var.app_security_group_id
  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
}

# Database

resource "aws_db_instance" "main" {
  identifier     = "${var.name}-db"
  engine         = "postgres"
  engine_version = "17"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name                     = "expenses"
  username                    = "expense_admin"
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  multi_az               = var.multi_az

  backup_retention_period = 1
  skip_final_snapshot     = true
}
