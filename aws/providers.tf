provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# Used only when enable_backup_cross_region_copy creates a DR-region backup vault.
provider "aws" {
  alias  = "dr"
  region = coalesce(var.backup_dr_region, var.aws_region)

  default_tags {
    tags = local.common_tags
  }
}
