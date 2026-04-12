# CloudWatch metric alarms (ALB + RDS) and ALB access logs (S3).
# Naming: alarm_name uses "${local.name_prefix}-..." per project convention.

data "aws_elb_service_account" "main" {}

# ---------- ALB access logs (S3, SSE-S3) ----------
resource "aws_s3_bucket" "alb_access_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = "${local.name_prefix}-alb-access-logs-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"

  tags = {
    Name = "${local.name_prefix}-alb-access-logs"
    Tier = "observability"
  }
}

resource "aws_s3_bucket_public_access_block" "alb_access_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_access_logs[0].id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "alb_access_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_access_logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  depends_on = [aws_s3_bucket_public_access_block.alb_access_logs]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_access_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_access_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_access_logs[0].id

  rule {
    id     = "expire-alb-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.alb_access_logs_retention_days
    }
  }

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.alb_access_logs]
}

data "aws_iam_policy_document" "alb_access_logs_bucket" {
  count = var.enable_alb_access_logs ? 1 : 0

  statement {
    sid    = "ELBServiceAccountPut"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }

    actions = [
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.alb_access_logs[0].arn}/${var.alb_access_logs_s3_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
    ]
  }

  statement {
    sid    = "ELBLogDeliveryPut"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }

    actions = [
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.alb_access_logs[0].arn}/${var.alb_access_logs_s3_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "ELBLogDeliveryAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }

    actions = [
      "s3:GetBucketAcl",
    ]

    resources = [
      aws_s3_bucket.alb_access_logs[0].arn,
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_access_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_access_logs[0].id
  policy = data.aws_iam_policy_document.alb_access_logs_bucket[0].json

  depends_on = [
    aws_s3_bucket_ownership_controls.alb_access_logs,
    aws_s3_bucket_public_access_block.alb_access_logs,
  ]
}

# ---------- CloudWatch: ALB ----------
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  count = var.enable_cloudwatch_alb_alarms && var.cloudwatch_alarm_alb_unhealthy_hosts_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-alb-unhealthy-hosts"
  alarm_description   = "ALB target group has unhealthy hosts (sustained)."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_alb_unhealthy_evaluation_periods
  datapoints_to_alarm = var.cloudwatch_alarm_alb_unhealthy_datapoints_to_alarm
  threshold           = 0
  treat_missing_data  = "notBreaching"

  metric_name = "UnHealthyHostCount"
  namespace   = "AWS/ApplicationELB"
  period      = var.cloudwatch_alarm_alb_unhealthy_period_seconds
  statistic   = "Maximum"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }

  alarm_actions = var.cloudwatch_alarm_sns_topic_arns
  ok_actions    = var.cloudwatch_alarm_sns_topic_arns
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  count = var.enable_cloudwatch_alb_alarms && var.cloudwatch_alarm_alb_target_5xx_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-alb-target-5xx"
  alarm_description   = "ALB reports elevated HTTP 5xx responses from targets."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_alb_5xx_evaluation_periods
  datapoints_to_alarm = var.cloudwatch_alarm_alb_5xx_datapoints_to_alarm
  threshold           = var.cloudwatch_alarm_alb_5xx_threshold
  treat_missing_data  = "notBreaching"

  metric_name = "HTTPCode_Target_5XX_Count"
  namespace   = "AWS/ApplicationELB"
  period      = var.cloudwatch_alarm_alb_5xx_period_seconds
  statistic   = "Sum"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }

  alarm_actions = var.cloudwatch_alarm_sns_topic_arns
  ok_actions    = var.cloudwatch_alarm_sns_topic_arns
}

resource "aws_cloudwatch_metric_alarm" "alb_target_response_time" {
  count = var.enable_cloudwatch_alb_alarms && var.cloudwatch_alarm_alb_target_response_time_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-alb-target-response-time"
  alarm_description   = "ALB target response time (average) exceeds threshold."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_alb_latency_evaluation_periods
  datapoints_to_alarm = var.cloudwatch_alarm_alb_latency_datapoints_to_alarm
  threshold           = var.cloudwatch_alarm_alb_target_response_time_threshold_seconds
  treat_missing_data  = "notBreaching"

  metric_name = "TargetResponseTime"
  namespace   = "AWS/ApplicationELB"
  period      = var.cloudwatch_alarm_alb_latency_period_seconds
  statistic   = "Average"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }

  alarm_actions = var.cloudwatch_alarm_sns_topic_arns
  ok_actions    = var.cloudwatch_alarm_sns_topic_arns
}

# ---------- CloudWatch: RDS ----------
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  count = var.enable_cloudwatch_rds_alarms && var.cloudwatch_alarm_rds_cpu_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-rds-cpu-high"
  alarm_description   = "RDS CPU utilization is above threshold."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_rds_cpu_evaluation_periods
  datapoints_to_alarm = var.cloudwatch_alarm_rds_cpu_datapoints_to_alarm
  threshold           = var.cloudwatch_alarm_rds_cpu_threshold_percent
  treat_missing_data  = "notBreaching"

  metric_name = "CPUUtilization"
  namespace   = "AWS/RDS"
  period      = var.cloudwatch_alarm_rds_cpu_period_seconds
  statistic   = "Average"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  alarm_actions = var.cloudwatch_alarm_sns_topic_arns
  ok_actions    = var.cloudwatch_alarm_sns_topic_arns
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage_low" {
  count = var.enable_cloudwatch_rds_alarms && var.cloudwatch_alarm_rds_free_storage_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-rds-free-storage-low"
  alarm_description   = "RDS free storage has fallen below threshold (bytes in CloudWatch)."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_rds_storage_evaluation_periods
  datapoints_to_alarm = var.cloudwatch_alarm_rds_storage_datapoints_to_alarm
  threshold           = local.rds_free_storage_alarm_threshold_bytes
  treat_missing_data  = "notBreaching"

  metric_name = "FreeStorageSpace"
  namespace   = "AWS/RDS"
  period      = var.cloudwatch_alarm_rds_storage_period_seconds
  statistic   = "Average"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  alarm_actions = var.cloudwatch_alarm_sns_topic_arns
  ok_actions    = var.cloudwatch_alarm_sns_topic_arns
}

resource "aws_cloudwatch_metric_alarm" "rds_database_connections" {
  count = var.enable_cloudwatch_rds_alarms && var.cloudwatch_alarm_rds_connections_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-rds-db-connections-high"
  alarm_description   = "RDS database connections exceed threshold."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_rds_connections_evaluation_periods
  datapoints_to_alarm = var.cloudwatch_alarm_rds_connections_datapoints_to_alarm
  threshold           = var.cloudwatch_alarm_rds_database_connections_threshold
  treat_missing_data  = "notBreaching"

  metric_name = "DatabaseConnections"
  namespace   = "AWS/RDS"
  period      = var.cloudwatch_alarm_rds_connections_period_seconds
  statistic   = "Average"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  alarm_actions = var.cloudwatch_alarm_sns_topic_arns
  ok_actions    = var.cloudwatch_alarm_sns_topic_arns
}
