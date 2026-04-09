output "environment" {
  description = "Active environment name for this deployment."
  value       = var.environment
}

output "aws_region" {
  description = "AWS region for this stack."
  value       = var.aws_region
}

output "name_prefix" {
  description = "Computed name prefix for resources (project-environment)."
  value       = local.name_prefix
}
