###############################################################################
# Blog resources.

# ACM certificate for TLS.
resource "aws_acm_certificate" "cert" {
  provider          = aws.cloudfront-acm-certs

  domain_name       = var.domain
  validation_method = "DNS"

  tags = merge(local.common_tags, {Name="${local.namespace}-cert"})

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution module, that also creates S3 bucket as website origin.
module "cdn" {
  source                   = "git::https://github.com/cloudposse/terraform-aws-cloudfront-s3-cdn.git?ref=tags/0.30.0"
  acm_certificate_arn      = aws_acm_certificate.cert.arn
  namespace                = local.namespace
  comment                  = var.cdn_comment
  name                     = "${local.namespace}-cdn"
  origin_force_destroy     = true
  compress                 = true
  logging_enabled          = false
  minimum_protocol_version = "TLSv1.2_2019"
  custom_error_response	= [
    {
      error_caching_min_ttl = "60"
      error_code            = "404"
      response_code         = "404"
      response_page_path    = "/404.html"
    }
  ]
  aliases = [var.domain]

  tags = local.common_tags

  # Requires terraform 0.13
  # depends_on = [aws_acm_certificate_validation.cert]
}

# Block public access directly to the bucket.
resource "aws_s3_bucket_public_access_block" "origin_bucket_access_block" {
  bucket                  = module.cdn.s3_bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# This resource requires having a registered domain in Route53.
# You have to purchase the domain and wait until it is registered.
resource "aws_route53_zone" "primary" {
  name          = var.domain
  comment       = "Hosted zone for ${var.domain}"
  force_destroy = true

  tags = merge(local.common_tags, {Name = "${local.namespace}-zone"})
}

# Records for DNS certificate validation.
resource "aws_route53_record" "cert_records" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.primary.zone_id
}

# Represents a successful DNS certificate validation.
# Creating this resource might take some time, as terraform will wait until the cert
# is validated and ready to use. Not validated certificates cannot be attached to CDN.
resource "aws_acm_certificate_validation" "cert" {
  provider                = aws.cloudfront-acm-certs

  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_records : record.fqdn]
}

# Alias record redirecting IPv4 traffic to CDN distribution.
resource "aws_route53_record" "blog_ipv4" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = module.cdn.cf_domain_name
    zone_id                = module.cdn.cf_hosted_zone_id
    evaluate_target_health = false
  }
}

# Alias record redirecting IPv6 traffic to CDN distribution.
resource "aws_route53_record" "blog_ipv6" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = var.domain
  type    = "AAAA"

  alias {
    name                   = module.cdn.cf_domain_name
    zone_id                = module.cdn.cf_hosted_zone_id
    evaluate_target_health = false
  }
}

# Resource group aggregating all elements required to host website.
resource "aws_resourcegroups_group" "blog" {
  name        = "${local.namespace}-resources"
  description = "Resources for personal blog."

  tags = merge(local.common_tags, {Name = "${local.namespace}-rg"})

  resource_query {
    query = <<JSON
{
  "ResourceTypeFilters": [
    "AWS::AllSupported"
  ],
  "TagFilters": [
    {
      "Key": "Project",
      "Values": ["${local.common_tags.Project}"]
    },
    {
      "Key": "Environment",
      "Values": ["${local.common_tags.Environment}"]
    }
  ]
}
JSON
  }
}
