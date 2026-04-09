locals {
  # Naming convention for AWS Name tags and resource identifiers:
  #   <project>-<environment>-<component>
  # Example: three-tier-webapp-prod-vpc
  # Use: "${local.name_prefix}-<component>" where <component> is short and stable (vpc, alb, app-asg, rds).
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }
}
