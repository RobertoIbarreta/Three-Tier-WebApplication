variable "aws_region" {
  type        = string
  description = "Region for the state bucket and lock table."
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name dedicated to Terraform remote state."

  validation {
    condition     = length(var.state_bucket_name) >= 3 && length(var.state_bucket_name) <= 63
    error_message = "state_bucket_name must be a valid S3 bucket name length (3-63)."
  }
}

variable "dynamodb_table_name" {
  type        = string
  default     = "terraform-state-locks"
  description = "DynamoDB table name for Terraform state locking (unique per account and region)."

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]+$", var.dynamodb_table_name))
    error_message = "dynamodb_table_name must contain only letters, numbers, hyphens, underscores, and dots."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Optional tags for bootstrap resources (e.g. Project, Owner)."
}
