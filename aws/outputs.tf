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
