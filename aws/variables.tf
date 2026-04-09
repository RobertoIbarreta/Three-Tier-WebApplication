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

# ---------- Compute / App Tier ----------
variable "instance_type" {
  type        = string
  description = "EC2 instance type for the application tier."
}

variable "app_port" {
  type        = number
  description = "Application listen port for target group and security rules."
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

# ---------- Load Balancer ----------
variable "alb_ingress_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the ALB (e.g. 0.0.0.0/0 for public HTTP)."
}

variable "health_check_path" {
  type        = string
  description = "HTTP path for ALB target group health checks."
}

# ---------- Database Tier ----------
variable "db_engine" {
  type        = string
  description = "RDS engine (e.g. mysql, postgres)."
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

variable "db_port" {
  type        = number
  description = "Database port."
}

variable "db_backup_retention" {
  type        = number
  description = "Backup retention period in days."
}

variable "db_multi_az" {
  type        = bool
  description = "Enable Multi-AZ for RDS."
}

variable "db_publicly_accessible" {
  type        = bool
  description = "Whether RDS is publicly accessible (should be false for private tier)."
}
