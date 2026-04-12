# AWS Backup: primary vault in aws_region; optional cross-region copy to aws.dr (DR narrative).

check "backup_cross_region_requires_dr_region" {
  assert {
    condition = (
      !var.enable_backup_cross_region_copy ||
      (var.backup_dr_region != null && var.backup_dr_region != var.aws_region)
    )
    error_message = "enable_backup_cross_region_copy requires backup_dr_region to be set and different from aws_region."
  }
}

resource "aws_backup_vault" "main" {
  count = var.enable_aws_backup ? 1 : 0

  name = "${local.name_prefix}-backup"

  tags = {
    Name = "${local.name_prefix}-backup"
    Tier = "data"
  }
}

resource "aws_backup_vault" "dr" {
  provider = aws.dr
  count    = var.enable_aws_backup && var.enable_backup_cross_region_copy ? 1 : 0

  name = "${local.name_prefix}-backup-dr"

  tags = {
    Name = "${local.name_prefix}-backup-dr"
    Tier = "data"
  }
}

resource "aws_iam_role" "backup" {
  count = var.enable_aws_backup ? 1 : 0

  name = "${local.name_prefix}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-backup-role"
    Tier = "data"
  }
}

resource "aws_iam_role_policy_attachment" "backup_service" {
  count = var.enable_aws_backup ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restores" {
  count = var.enable_aws_backup ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_iam_role_policy_attachment" "backup_s3_backup" {
  count = var.enable_aws_backup && var.enable_backup_s3_frontend ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForS3Backup"
}

resource "aws_iam_role_policy_attachment" "backup_s3_restore" {
  count = var.enable_aws_backup && var.enable_backup_s3_frontend ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForS3Restore"
}

resource "aws_backup_plan" "main" {
  count = var.enable_aws_backup ? 1 : 0

  name = "${local.name_prefix}-backup-plan"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.main[0].name
    schedule          = var.backup_plan_schedule_cron
    start_window      = var.backup_plan_start_window_minutes
    completion_window = var.backup_plan_completion_window_minutes

    lifecycle {
      delete_after = var.backup_plan_retention_days
    }

    dynamic "copy_action" {
      for_each = var.enable_backup_cross_region_copy ? [1] : []
      content {
        destination_vault_arn = aws_backup_vault.dr[0].arn

        lifecycle {
          delete_after = var.backup_cross_region_retention_days
        }
      }
    }
  }

  tags = {
    Name = "${local.name_prefix}-backup-plan"
    Tier = "data"
  }
}

resource "aws_backup_selection" "main" {
  count = var.enable_aws_backup ? 1 : 0

  name         = "${local.name_prefix}-backup-selection"
  iam_role_arn = aws_iam_role.backup[0].arn
  plan_id      = aws_backup_plan.main[0].id

  resources = concat(
    [aws_db_instance.main.arn],
    var.enable_backup_s3_frontend ? [aws_s3_bucket.frontend.arn] : []
  )

  # Ensure IAM policies exist before Backup evaluates the selection.
  depends_on = [
    aws_iam_role_policy_attachment.backup_service,
    aws_iam_role_policy_attachment.backup_restores,
    aws_iam_role_policy_attachment.backup_s3_backup,
    aws_iam_role_policy_attachment.backup_s3_restore,
  ]
}
