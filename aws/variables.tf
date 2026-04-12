# ---------- Global ----------
# Naming: resource names and Name tags should follow
#   <project>-<environment>-<component>
# (see locals.name_prefix; append a hyphen and component slug per resource.)
variable "project_name" {
  type        = string
  description = "Project slug for names and tags; prefer lowercase letters, digits, hyphens (e.g. three-tier-webapp)."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric with hyphens only."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, stage, prod); second segment in <project>-<env>-<component> names."

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage, or prod."
  }
}

variable "owner" {
  type        = string
  description = "Owning team or contact for required tag Owner (e.g. team-platform, email alias, or internal ID)."

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must be a non-empty string."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for this stack."
}

# ---------- Networking ----------
variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets (typically one per AZ)."
}

variable "private_app_subnets" {
  type        = list(string)
  description = "CIDR blocks for private application subnets."
}

variable "private_db_subnets" {
  type        = list(string)
  description = "CIDR blocks for private database subnets."
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones to use (must match subnet count strategy)."
}

# ---------- SSM Session Manager (optional VPC endpoints) ----------
variable "enable_ssm_vpc_endpoints" {
  type        = bool
  description = "When true, create interface VPC endpoints for SSM, SSMMessages, and EC2Messages in private app subnets so instances can use Session Manager without reaching public AWS API endpoints (adds cost; NAT alone is enough for typical use)."
  default     = false
}

# ---------- Compute / App Tier ----------
variable "instance_type" {
  type        = string
  description = "EC2 instance type for the application tier."
}

variable "app_port" {
  type        = number
  description = "Application listen port for target group and security rules."
}

variable "app_health_check_path" {
  type        = string
  description = "Application health endpoint path used by bootstrap/app config. If null, falls back to health_check_path."
  default     = null
  nullable    = true
}

variable "app_bootstrap_extra_commands" {
  type        = string
  description = "Optional extra shell commands appended to launch-template user data bootstrap."
  default     = ""
}

variable "asg_min_size" {
  type        = number
  description = "Auto Scaling Group minimum capacity."
}

variable "asg_desired_capacity" {
  type        = number
  description = "Auto Scaling Group desired capacity."
}

variable "asg_max_size" {
  type        = number
  description = "Auto Scaling Group maximum capacity."
}

variable "asg_target_requests_per_target" {
  type        = number
  description = "Target ALB requests per target for ASG target tracking."
  default     = 100
}

# ---------- Load Balancer ----------
variable "alb_ingress_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the ALB (e.g. 0.0.0.0/0 for public HTTP)."
}

variable "health_check_path" {
  type        = string
  description = "HTTP path for ALB target group health checks."
}

variable "acm_certificate_arn" {
  type        = string
  description = "Existing ACM certificate ARN for ALB HTTPS listener."
}

variable "enable_http_to_https_redirect" {
  type        = bool
  description = "Whether HTTP listener redirects traffic to HTTPS."
  default     = true
}

# ---------- WAFv2 (regional, ALB) ----------
variable "enable_waf" {
  type        = bool
  description = "When true, attach a regional WAFv2 web ACL to the ALB (AWS managed rule groups; monthly cost). Set false in dev to save money."
  default     = true
}

variable "waf_managed_rule_overrides" {
  type        = map(list(string))
  description = "Optional tuning: map AWS managed rule group name to rule names that should use COUNT instead of the group default (e.g. {\"AWSManagedRulesCommonRuleSet\" = [\"SizeRestrictions_BODY\"]}). Keys must match group names used in waf.tf. AWSManagedRulesSQLiRuleSet applies to SQL-like payloads in requests; it is not engine-specific to MySQL vs Postgres—tune with overrides if a rule false-positives on your API."
  default     = {}
}

# ---------- AWS Backup + DR (RDS; optional S3 frontend) ----------
variable "enable_aws_backup" {
  type        = bool
  description = "When true, create a backup vault, IAM role, plan, and selection for RDS (and optionally S3). Set false in dev to reduce cost/complexity."
  default     = true
}

variable "backup_plan_schedule_cron" {
  type        = string
  description = "AWS Backup schedule expression (cron) for the daily rule, UTC. Example: cron(0 6 ? * * *) = 06:00 daily."
  default     = "cron(0 6 ? * * *)"
}

variable "backup_plan_start_window_minutes" {
  type        = number
  description = "Start window in minutes after scheduled time for AWS Backup to begin a job."
  default     = 60
}

variable "backup_plan_completion_window_minutes" {
  type        = number
  description = "Maximum time in minutes for AWS Backup to complete a job."
  default     = 180
}

variable "backup_plan_retention_days" {
  type        = number
  description = "Retention in days for recovery points in the primary backup vault (lifecycle delete_after)."
  default     = 35

  validation {
    condition     = var.backup_plan_retention_days >= 1
    error_message = "backup_plan_retention_days must be at least 1."
  }
}

variable "enable_backup_cross_region_copy" {
  type        = bool
  description = "When true, copy each recovery point to a vault in backup_dr_region (second provider alias). Keep false in dev (single-region)."
  default     = false
}

variable "backup_dr_region" {
  type        = string
  description = "Destination AWS region for cross-region backup copies; required when enable_backup_cross_region_copy is true (must differ from aws_region)."
  default     = null
  nullable    = true
}

variable "backup_cross_region_retention_days" {
  type        = number
  description = "Retention in days for recovery points in the DR-region backup vault (copy_action lifecycle)."
  default     = 35

  validation {
    condition     = var.backup_cross_region_retention_days >= 1
    error_message = "backup_cross_region_retention_days must be at least 1."
  }
}

variable "enable_backup_s3_frontend" {
  type        = bool
  description = "When true and enable_aws_backup is true, include the frontend S3 bucket in the backup selection and attach S3 backup/restore managed policies to the backup role. Requires S3 backup support in the region; otherwise rely on versioning + lifecycle only."
  default     = false
}

# ---------- Route53 (existing public hosted zone) ----------
variable "route53_zone_id" {
  type        = string
  description = "Route53 public hosted zone ID (e.g. Z123...) for alias records. When null, no Route53 records are managed here."
  default     = null
  nullable    = true
}

variable "api_dns_name" {
  type        = string
  description = "FQDN for the API (e.g. api.example.com). When set with route53_zone_id, creates an alias A record to the ALB (evaluate_target_health = true). Use an ACM cert on the ALB that covers this name."
  default     = null
  nullable    = true
}

variable "frontend_domain_name" {
  type        = string
  description = "Optional custom domain (FQDN) for the frontend. Drives CloudFront aliases (with frontend_acm_certificate_arn) and, when route53_zone_id is set, Route53 alias A/AAAA records to CloudFront—the same hostname everywhere; do not introduce a second frontend DNS variable."
  default     = null
  nullable    = true
}

variable "frontend_acm_certificate_arn" {
  type        = string
  description = "Optional ACM certificate ARN in us-east-1 for CloudFront custom domain."
  default     = null
  nullable    = true
}

variable "frontend_index_document" {
  type        = string
  description = "Default index document for frontend static hosting."
  default     = "index.html"
}

variable "frontend_error_document" {
  type        = string
  description = "Default error document for SPA fallback behavior."
  default     = "index.html"
}

variable "frontend_noncurrent_version_expiration_days" {
  type        = number
  description = "Expire noncurrent S3 object versions in the frontend bucket after this many days (bounds versioning storage cost)."
  default     = 90

  validation {
    condition     = var.frontend_noncurrent_version_expiration_days >= 1
    error_message = "frontend_noncurrent_version_expiration_days must be at least 1."
  }
}

variable "backend_allowed_origins" {
  type        = list(string)
  description = "List of allowed origins for backend CORS (include CloudFront/custom frontend URL)."
  default     = []
}

# ---------- Database Tier ----------
variable "db_engine" {
  type        = string
  description = "RDS engine (e.g. mysql, postgres)."
}

variable "db_parameter_group_family" {
  type        = string
  description = "DB parameter group family matching the selected engine/version (e.g. postgres16, mysql8.0)."
}

variable "db_engine_version" {
  type        = string
  description = "RDS engine version."
}

variable "db_instance_class" {
  type        = string
  description = "RDS instance class."
}

variable "db_allocated_storage" {
  type        = number
  description = "Allocated storage in GB (engine-dependent minimums apply)."
}

variable "db_name" {
  type        = string
  description = "Initial database name."
}

variable "db_username" {
  type        = string
  description = "Master username for RDS (password via secret, not in tfvars in git)."
}

variable "db_password" {
  type        = string
  description = "Master password for RDS."
  sensitive   = true
}

variable "db_port" {
  type        = number
  description = "Database port."
}

variable "db_backup_retention" {
  type        = number
  description = "Backup retention period in days."
}

variable "db_maintenance_window" {
  type        = string
  description = "Weekly maintenance window in UTC (e.g. Mon:03:00-Mon:04:00)."
}

variable "db_multi_az" {
  type        = bool
  description = "Enable Multi-AZ for RDS."
}

variable "db_skip_final_snapshot" {
  type        = bool
  description = "Whether to skip final snapshot when destroying DB (use true for ephemeral envs, false for prod)."
}

variable "db_publicly_accessible" {
  type        = bool
  description = "Whether RDS is publicly accessible (should be false for private tier)."
}

# ---------- Observability: ALB access logs (S3) ----------
variable "enable_alb_access_logs" {
  type        = bool
  description = "When true, create a dedicated S3 bucket and enable ALB access logging (storage cost; disable in dev to save money)."
  default     = true
}

variable "alb_access_logs_s3_prefix" {
  type        = string
  description = "S3 key prefix for ALB access logs (must not contain the literal 'AWSLogs')."
  default     = "alb"

  validation {
    condition     = !can(regex("AWSLogs", var.alb_access_logs_s3_prefix))
    error_message = "alb_access_logs_s3_prefix must not contain the substring AWSLogs."
  }
}

variable "alb_access_logs_retention_days" {
  type        = number
  description = "S3 lifecycle expiration for ALB access log objects (days)."
  default     = 90
}

# ---------- Observability: CloudWatch alarms ----------
variable "enable_cloudwatch_alb_alarms" {
  type        = bool
  description = "Master switch for ALB CloudWatch metric alarms."
  default     = true
}

variable "enable_cloudwatch_rds_alarms" {
  type        = bool
  description = "Master switch for RDS CloudWatch metric alarms."
  default     = true
}

variable "cloudwatch_alarm_sns_topic_arns" {
  type        = list(string)
  description = "Optional SNS topic ARNs for alarm OK and ALARM notifications (empty = console only)."
  default     = []
}

# ALB: unhealthy hosts (sustained)
variable "cloudwatch_alarm_alb_unhealthy_hosts_enabled" {
  type        = bool
  description = "When true (and ALB alarms enabled), alarm if UnHealthyHostCount > 0."
  default     = true
}

variable "cloudwatch_alarm_alb_unhealthy_period_seconds" {
  type        = number
  description = "Period for UnHealthyHostCount alarm (seconds)."
  default     = 60
}

variable "cloudwatch_alarm_alb_unhealthy_evaluation_periods" {
  type        = number
  description = "Evaluation periods for unhealthy host alarm (sustained signal)."
  default     = 3
}

variable "cloudwatch_alarm_alb_unhealthy_datapoints_to_alarm" {
  type        = number
  description = "Datapoints breaching threshold before ALARM for unhealthy hosts."
  default     = 3
}

# ALB: target 5xx
variable "cloudwatch_alarm_alb_target_5xx_enabled" {
  type        = bool
  description = "When true, alarm on HTTPCode_Target_5XX_Count sum over the period."
  default     = true
}

variable "cloudwatch_alarm_alb_5xx_period_seconds" {
  type        = number
  description = "Period for target 5xx alarm (seconds)."
  default     = 300
}

variable "cloudwatch_alarm_alb_5xx_evaluation_periods" {
  type        = number
  description = "Evaluation periods for target 5xx alarm."
  default     = 1
}

variable "cloudwatch_alarm_alb_5xx_datapoints_to_alarm" {
  type        = number
  description = "Datapoints breaching threshold before ALARM for target 5xx."
  default     = 1
}

variable "cloudwatch_alarm_alb_5xx_threshold" {
  type        = number
  description = "Sum of HTTPCode_Target_5XX_Count per period above which to alarm."
  default     = 10
}

# ALB: target response time (optional / higher noise)
variable "cloudwatch_alarm_alb_target_response_time_enabled" {
  type        = bool
  description = "When true, alarm when average TargetResponseTime exceeds threshold (seconds)."
  default     = false
}

variable "cloudwatch_alarm_alb_latency_period_seconds" {
  type        = number
  description = "Period for target response time alarm (seconds)."
  default     = 300
}

variable "cloudwatch_alarm_alb_latency_evaluation_periods" {
  type        = number
  description = "Evaluation periods for target response time alarm."
  default     = 2
}

variable "cloudwatch_alarm_alb_latency_datapoints_to_alarm" {
  type        = number
  description = "Datapoints breaching threshold before ALARM for target response time."
  default     = 2
}

variable "cloudwatch_alarm_alb_target_response_time_threshold_seconds" {
  type        = number
  description = "Average TargetResponseTime (seconds) above which to alarm."
  default     = 5
}

# RDS: CPU
variable "cloudwatch_alarm_rds_cpu_enabled" {
  type        = bool
  description = "When true, alarm when CPUUtilization exceeds threshold (percent)."
  default     = true
}

variable "cloudwatch_alarm_rds_cpu_period_seconds" {
  type        = number
  description = "Period for RDS CPU alarm (seconds)."
  default     = 300
}

variable "cloudwatch_alarm_rds_cpu_evaluation_periods" {
  type        = number
  description = "Evaluation periods for RDS CPU alarm."
  default     = 2
}

variable "cloudwatch_alarm_rds_cpu_datapoints_to_alarm" {
  type        = number
  description = "Datapoints breaching threshold before ALARM for RDS CPU."
  default     = 2
}

variable "cloudwatch_alarm_rds_cpu_threshold_percent" {
  type        = number
  description = "CPU utilization percent above which to alarm."
  default     = 80
}

# RDS: free storage (CloudWatch metric is bytes; threshold via GiB)
variable "cloudwatch_alarm_rds_free_storage_enabled" {
  type        = bool
  description = "When true, alarm when FreeStorageSpace falls below cloudwatch_alarm_rds_free_storage_min_gib."
  default     = true
}

variable "cloudwatch_alarm_rds_storage_period_seconds" {
  type        = number
  description = "Period for RDS free storage alarm (seconds)."
  default     = 300
}

variable "cloudwatch_alarm_rds_storage_evaluation_periods" {
  type        = number
  description = "Evaluation periods for RDS free storage alarm."
  default     = 1
}

variable "cloudwatch_alarm_rds_storage_datapoints_to_alarm" {
  type        = number
  description = "Datapoints breaching threshold before ALARM for RDS free storage."
  default     = 1
}

variable "cloudwatch_alarm_rds_free_storage_min_gib" {
  type        = number
  description = "Alarm when RDS FreeStorageSpace (bytes) average drops below this many gibibytes."
  default     = 2
}

# RDS: connections
variable "cloudwatch_alarm_rds_connections_enabled" {
  type        = bool
  description = "When true, alarm when DatabaseConnections exceeds threshold."
  default     = true
}

variable "cloudwatch_alarm_rds_connections_period_seconds" {
  type        = number
  description = "Period for RDS database connections alarm (seconds)."
  default     = 300
}

variable "cloudwatch_alarm_rds_connections_evaluation_periods" {
  type        = number
  description = "Evaluation periods for RDS connections alarm."
  default     = 2
}

variable "cloudwatch_alarm_rds_connections_datapoints_to_alarm" {
  type        = number
  description = "Datapoints breaching threshold before ALARM for RDS connections."
  default     = 2
}

variable "cloudwatch_alarm_rds_database_connections_threshold" {
  type        = number
  description = "DatabaseConnections average above which to alarm (tune per engine/workload)."
  default     = 80
}
