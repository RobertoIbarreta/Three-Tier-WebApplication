# Regional WAFv2 in front of the ALB (traffic: client -> WAF -> ALB). Route53 aliases still target the ALB DNS name.

resource "aws_wafv2_web_acl" "alb" {
  count = var.enable_waf ? 1 : 0

  name        = "${local.name_prefix}-alb-waf"
  description = "Regional WAF for the public application load balancer."
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${replace(local.name_prefix, "-", "_")}_alb_waf"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        dynamic "rule_action_override" {
          for_each = toset(try(var.waf_managed_rule_overrides["AWSManagedRulesCommonRuleSet"], []))
          content {
            name = rule_action_override.value
            action_to_use {
              count {}
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${replace(local.name_prefix, "-", "_")}_waf_common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"

        dynamic "rule_action_override" {
          for_each = toset(try(var.waf_managed_rule_overrides["AWSManagedRulesKnownBadInputsRuleSet"], []))
          content {
            name = rule_action_override.value
            action_to_use {
              count {}
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${replace(local.name_prefix, "-", "_")}_waf_bad_inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"

        dynamic "rule_action_override" {
          for_each = toset(try(var.waf_managed_rule_overrides["AWSManagedRulesSQLiRuleSet"], []))
          content {
            name = rule_action_override.value
            action_to_use {
              count {}
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${replace(local.name_prefix, "-", "_")}_waf_sqli"
      sampled_requests_enabled   = true
    }
  }

  tags = {
    Name = "${local.name_prefix}-alb-waf"
    Tier = "public"
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_lb.app.arn
  web_acl_arn  = aws_wafv2_web_acl.alb[0].arn
}
