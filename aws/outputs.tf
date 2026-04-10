output "environment" {
  description = "Active environment name for this deployment."
  value       = var.environment
}

output "aws_region" {
  description = "AWS region for this stack."
  value       = var.aws_region
}

output "name_prefix" {
  description = "Prefix for <project>-<environment>-<component> naming; append -<component> per resource."
  value       = local.name_prefix
}

output "common_tags" {
  description = "Default tags applied via provider default_tags (Project, Environment, ManagedBy, Owner)."
  value       = local.common_tags
}

output "vpc_id" {
  description = "ID of the main VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets created across configured AZs."
  value       = values(aws_subnet.public)[*].id
}

output "private_app_subnet_ids" {
  description = "IDs of private application subnets created across configured AZs."
  value       = values(aws_subnet.private_app)[*].id
}

output "private_db_subnet_ids" {
  description = "IDs of private database subnets created across configured AZs."
  value       = values(aws_subnet.private_db)[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway attached to the VPC."
  value       = aws_internet_gateway.main.id
}

output "public_route_table_id" {
  description = "ID of the public route table (default route to IGW)."
  value       = aws_route_table.public.id
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs keyed by subnet/AZ index."
  value       = { for k, v in aws_nat_gateway.main : k => v.id }
}

output "private_app_route_table_ids" {
  description = "Private app route table IDs keyed by subnet/AZ index."
  value       = { for k, v in aws_route_table.private_app : k => v.id }
}

output "private_db_route_table_ids" {
  description = "Private DB route table IDs keyed by subnet/AZ index (no direct IGW route)."
  value       = { for k, v in aws_route_table.private_db : k => v.id }
}
