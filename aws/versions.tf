terraform {
  required_version = ">= 1.5.0"

  # Partial backend: pass bucket, key, region, dynamodb_table, encrypt at init:
  #   terraform init -backend-config=environments/<env>/backend.hcl
  # Use -migrate-state when moving from local state to S3.
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
