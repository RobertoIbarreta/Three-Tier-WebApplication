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

  # CloudWatch FreeStorageSpace is in bytes; variable is GiB for operator-friendly thresholds.
  rds_free_storage_alarm_threshold_bytes = floor(var.cloudwatch_alarm_rds_free_storage_min_gib * 1073741824)

  route53_zone_configured = var.route53_zone_id != null && var.route53_zone_id != ""

  route53_api_record_enabled = (
    local.route53_zone_configured &&
    var.api_dns_name != null &&
    var.api_dns_name != ""
  )

  route53_frontend_records_enabled = (
    local.route53_zone_configured &&
    var.frontend_domain_name != null &&
    var.frontend_domain_name != ""
  )
}
