# RDS master user password is managed by RDS in Secrets Manager (manage_master_user_password).
# Do not duplicate the password into SSM Parameter Store from Terraform (rotation/drift risk).
# App tier: use the instance profile role to call GetSecretValue on the secret ARN (output
# db_master_user_secret_arn); parse the JSON payload for host, port, username, password.

data "aws_iam_policy_document" "app_ec2_rds_master_secret" {
  statement {
    sid    = "GetRdsMasterUserSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [aws_db_instance.main.master_user_secret[0].secret_arn]
  }

  statement {
    sid    = "DecryptRdsMasterSecret"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
    ]
    resources = [aws_db_instance.main.master_user_secret[0].kms_key_id]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "app_ec2_rds_master_secret" {
  name   = "${local.name_prefix}-app-ec2-rds-master-secret"
  role   = aws_iam_role.app_ec2.id
  policy = data.aws_iam_policy_document.app_ec2_rds_master_secret.json
}
