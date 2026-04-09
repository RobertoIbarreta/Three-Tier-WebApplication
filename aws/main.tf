resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

locals {
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
