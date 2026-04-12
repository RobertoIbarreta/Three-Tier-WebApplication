# Route53: alias records in an existing public hosted zone.
# Frontend hostname is var.frontend_domain_name only (shared with CloudFront aliases).

check "route53_api_requires_zone" {
  assert {
    condition = (
      var.api_dns_name == null ||
      var.api_dns_name == "" ||
      local.route53_zone_configured
    )
    error_message = "When api_dns_name is set, route53_zone_id must be set to the target public hosted zone ID."
  }
}

resource "aws_route53_record" "api_a" {
  count = local.route53_api_record_enabled ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.api_dns_name
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}

# ALB is IPv4-only in this stack (no IPv6 on subnets). Add AAAA here when the ALB uses
# dual-stack and subnets have IPv6, mirroring the A record above.

resource "aws_route53_record" "frontend_a" {
  count = local.route53_frontend_records_enabled ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.frontend_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "frontend_aaaa" {
  count = local.route53_frontend_records_enabled ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.frontend_domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}
