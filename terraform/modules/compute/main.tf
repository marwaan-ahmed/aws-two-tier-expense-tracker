# Security group

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "App servers: port 8000 from the load balancer only"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-app"
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = var.alb_security_group_id
  from_port                    = 8000
  ip_protocol                  = "tcp"
  to_port                      = 8000
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "postgres" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 5432
  ip_protocol       = "tcp"
  to_port           = 5432
}

# App code

data "archive_file" "app" {
  type        = "zip"
  source_dir  = var.app_dir
  output_path = "${path.module}/app.zip"
  excludes    = ["__pycache__"]
}

resource "aws_s3_bucket" "app" {
  bucket_prefix = "${var.name}-app-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "app" {
  bucket = aws_s3_bucket.app.id
  key    = "app-${data.archive_file.app.output_md5}.zip"
  source = data.archive_file.app.output_path
}

# Logs

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.name}/app"
  retention_in_days = 7
}

# IAM

resource "aws_iam_role" "app" {
  name = "${var.name}-app"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "app" {
  name = "${var.name}-app"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "secretsmanager:GetSecretValue"
        Effect   = "Allow"
        Resource = var.db_secret_arn
      },
      {
        Action   = "s3:GetObject"
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.app.arn}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-app"
  role = aws_iam_role.app.name
}

# Launch template

resource "aws_launch_template" "app" {
  name          = "${var.name}-app"
  image_id      = "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
  instance_type = "t4g.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  metadata_options {
    http_tokens = "required"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      encrypted = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    region        = var.region
    app_bucket    = aws_s3_bucket.app.id
    app_key       = aws_s3_object.app.key
    db_host       = var.db_host
    db_name       = var.db_name
    db_secret_arn = var.db_secret_arn
    log_group     = aws_cloudwatch_log_group.app.name
  }))

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.name}-app"
    }
  }
}

# Auto Scaling group

resource "aws_autoscaling_group" "app" {
  name                = "${var.name}-app"
  min_size            = 2
  max_size            = 4
  vpc_zone_identifier = var.app_subnet_ids
  target_group_arns   = [var.target_group_arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.name}-cpu"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 50
  }
}
