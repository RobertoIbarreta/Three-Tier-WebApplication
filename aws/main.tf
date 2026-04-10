resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

data "aws_ssm_parameter" "al2_ami_id" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

resource "aws_iam_role" "app_ec2" {
  name = "${local.name_prefix}-app-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-app-ec2-role"
    Tier = "app"
  }
}

resource "aws_iam_role_policy_attachment" "app_ec2_ssm_core" {
  role       = aws_iam_role.app_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app_ec2" {
  name = "${local.name_prefix}-app-ec2-profile"
  role = aws_iam_role.app_ec2.name
}

resource "aws_launch_template" "app" {
  name_prefix   = "${local.name_prefix}-app-lt-"
  image_id      = data.aws_ssm_parameter.al2_ami_id.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.app_ec2.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = base64encode(<<-EOT
    #!/bin/bash
    set -euxo pipefail

    cat >/etc/profile.d/app_env.sh <<'EOF'
    export APP_PORT="${var.app_port}"
    export HEALTH_ENDPOINT="${local.app_health_check_path}"
    EOF
    chmod 644 /etc/profile.d/app_env.sh

    mkdir -p /opt/app
    cat >/opt/app/app.env <<'EOF'
    APP_PORT=${var.app_port}
    HEALTH_ENDPOINT=${local.app_health_check_path}
    EOF
    chmod 600 /opt/app/app.env

  EOT
  )

  network_interfaces {
    associate_public_ip_address = false
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name_prefix}-app"
      Tier = "app"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${local.name_prefix}-app-volume"
      Tier = "app"
    }
  }

  tags = {
    Name = "${local.name_prefix}-app-lt"
    Tier = "app"
  }
}

resource "aws_lb" "app" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = values(aws_subnet.public)[*].id

  tags = {
    Name = "${local.name_prefix}-alb"
    Tier = "public"
  }
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-app-tg"
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = local.app_health_check_path
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${local.name_prefix}-app-tg"
    Tier = "app"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_autoscaling_group" "app" {
  name             = "${local.name_prefix}-app-asg"
  min_size         = var.asg_min_size
  desired_capacity = var.asg_desired_capacity
  max_size         = var.asg_max_size

  vpc_zone_identifier = values(aws_subnet.private_app)[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Tier"
    value               = "app"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "app_alb_request_count" {
  name                   = "${local.name_prefix}-app-alb-req-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.app.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value = 100
  }
}

locals {
  app_health_check_path = var.health_check_path

  public_subnet_map = {
    for idx, cidr in var.public_subnet_cidrs : idx => {
      cidr = cidr
      az   = var.availability_zones[idx]
    }
  }

  private_app_subnet_map = {
    for idx, cidr in var.private_app_subnets : idx => {
      cidr = cidr
      az   = var.availability_zones[idx]
    }
  }

  private_db_subnet_map = {
    for idx, cidr in var.private_db_subnets : idx => {
      cidr = cidr
      az   = var.availability_zones[idx]
    }
  }

  # Derive an RDS parameter-group family from engine/version to avoid
  # environment drift and keep the value centrally computed.
  db_parameter_group_family = (
    var.db_engine == "postgres" ?
    "postgres${split(".", var.db_engine_version)[0]}" :
    var.db_engine == "mysql" ?
    "mysql${join(".", slice(split(".", var.db_engine_version), 0, 2))}" :
    var.db_engine
  )
}

resource "aws_subnet" "public" {
  for_each = local.public_subnet_map

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet-${each.key + 1}"
    Tier = "public"
  }
}

resource "aws_subnet" "private_app" {
  for_each = local.private_app_subnet_map

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = {
    Name = "${local.name_prefix}-private-app-subnet-${each.key + 1}"
    Tier = "app"
  }
}

resource "aws_subnet" "private_db" {
  for_each = local.private_db_subnet_map

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = {
    Name = "${local.name_prefix}-private-db-subnet-${each.key + 1}"
    Tier = "db"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
    Tier = "public"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  for_each = aws_subnet.public

  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip-${tonumber(each.key) + 1}"
    Tier = "public"
  }
}

resource "aws_nat_gateway" "main" {
  for_each = aws_subnet.public

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id

  tags = {
    Name = "${local.name_prefix}-nat-${tonumber(each.key) + 1}"
    Tier = "public"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private_app" {
  for_each = aws_subnet.private_app

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[each.key].id
  }

  tags = {
    Name = "${local.name_prefix}-private-app-rt-${tonumber(each.key) + 1}"
    Tier = "app"
  }
}

resource "aws_route_table_association" "private_app" {
  for_each = aws_subnet.private_app

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_app[each.key].id
}

resource "aws_route_table" "private_db" {
  for_each = aws_subnet.private_db

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-private-db-rt-${tonumber(each.key) + 1}"
    Tier = "db"
  }
}

resource "aws_route_table_association" "private_db" {
  for_each = aws_subnet.private_db

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_db[each.key].id
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB security group allowing public HTTP/HTTPS."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = aws_vpc.main.ipv6_cidr_block != null ? [1] : []
    content {
      description      = "Allow HTTP from internet (IPv6)"
      from_port        = 80
      to_port          = 80
      protocol         = "tcp"
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  dynamic "ingress" {
    for_each = aws_vpc.main.ipv6_cidr_block != null ? [1] : []
    content {
      description      = "Allow HTTPS from internet (IPv6)"
      from_port        = 443
      to_port          = 443
      protocol         = "tcp"
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "egress" {
    for_each = aws_vpc.main.ipv6_cidr_block != null ? [1] : []
    content {
      description      = "Allow all outbound traffic (IPv6)"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  tags = {
    Name = "${local.name_prefix}-alb-sg"
    Tier = "public"
  }
}

resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "Application security group allowing traffic only from ALB."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow app traffic from ALB security group"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "egress" {
    for_each = aws_vpc.main.ipv6_cidr_block != null ? [1] : []
    content {
      description      = "Allow all outbound traffic (IPv6)"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  tags = {
    Name = "${local.name_prefix}-app-sg"
    Tier = "app"
  }
}

resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-db-sg"
  description = "Database security group allowing traffic only from app tier."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow DB traffic from app security group"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "egress" {
    for_each = aws_vpc.main.ipv6_cidr_block != null ? [1] : []
    content {
      description      = "Allow all outbound traffic (IPv6)"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  tags = {
    Name = "${local.name_prefix}-db-sg"
    Tier = "db"
  }
}

resource "aws_db_subnet_group" "main" {
  name        = "${local.name_prefix}-db-subnet-group"
  description = "DB subnet group spanning private DB subnets."
  subnet_ids  = values(aws_subnet.private_db)[*].id

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
    Tier = "db"
  }
}

resource "aws_db_parameter_group" "main" {
  name        = "${local.name_prefix}-db-params"
  family      = local.db_parameter_group_family
  description = "Parameter group baseline for safe DB tuning over time."

  tags = {
    Name = "${local.name_prefix}-db-params"
    Tier = "db"
  }
}

resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption at rest."
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${local.name_prefix}-rds-kms"
    Tier = "db"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${local.name_prefix}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-db"

  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage           = var.db_allocated_storage
  db_name                     = var.db_name
  username                    = var.db_username
  manage_master_user_password = true
  port                        = var.db_port

  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention
  maintenance_window      = "Mon:03:00-Mon:04:00"

  publicly_accessible = false

  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.main.name

  tags = {
    Name = "${local.name_prefix}-db"
    Tier = "db"
  }
}
