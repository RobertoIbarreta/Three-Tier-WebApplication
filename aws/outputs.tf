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

output "db_instance_id" {
  description = "RDS DB instance identifier."
  value       = aws_db_instance.main.id
}

output "db_endpoint" {
  description = "RDS DB endpoint with port."
  value       = aws_db_instance.main.endpoint
}

output "db_address" {
  description = "RDS DB endpoint address (hostname only)."
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "RDS DB endpoint port."
  value       = aws_db_instance.main.port
}

output "db_subnet_group_name" {
  description = "DB subnet group name associated with the RDS instance."
  value       = aws_db_instance.main.db_subnet_group_name
}

output "db_publicly_accessible" {
  description = "Whether the DB instance is publicly accessible."
  value       = aws_db_instance.main.publicly_accessible
}

output "app_ec2_role_name" {
  description = "IAM role name used by app EC2 instances."
  value       = aws_iam_role.app_ec2.name
}

output "app_ec2_role_arn" {
  description = "IAM role ARN used by app EC2 instances."
  value       = aws_iam_role.app_ec2.arn
}

output "app_ec2_instance_profile_name" {
  description = "IAM instance profile name used by app EC2 instances."
  value       = aws_iam_instance_profile.app_ec2.name
}

output "app_ec2_instance_profile_arn" {
  description = "IAM instance profile ARN used by app EC2 instances."
  value       = aws_iam_instance_profile.app_ec2.arn
}

output "app_launch_template_id" {
  description = "ID of the application launch template."
  value       = aws_launch_template.app.id
}

output "app_launch_template_latest_version" {
  description = "Latest version number of the application launch template."
  value       = aws_launch_template.app.latest_version
}

output "app_launch_template_ami_id" {
  description = "Resolved AMI ID used by the application launch template."
  value       = data.aws_ssm_parameter.al2_ami_id.value
}

output "alb_dns_name" {
  description = "DNS name of the application load balancer."
  value       = aws_lb.app.dns_name
}

output "alb_arn" {
  description = "ARN of the application load balancer."
  value       = aws_lb.app.arn
}

output "app_target_group_arn" {
  description = "ARN of the application target group."
  value       = aws_lb_target_group.app.arn
}

output "app_asg_name" {
  description = "Name of the application Auto Scaling Group."
  value       = aws_autoscaling_group.app.name
}

output "app_scaling_policy_arn" {
  description = "ARN of the ASG target tracking scaling policy."
  value       = aws_autoscaling_policy.app_alb_request_count.arn
}

output "alb_https_listener_arn" {
  description = "ARN of the HTTPS listener for the application load balancer."
  value       = aws_lb_listener.https.arn
}

output "alb_https_endpoint" {
  description = "Convenience HTTPS endpoint URL for the application load balancer."
  value       = "https://${aws_lb.app.dns_name}"
}
