###############################################################################
# Variables.

# AWS default region.
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# Blog domain name.
variable "domain" {
  type    = string
  default = "basz.co.uk"
}

###############################################################################
# Providers.

provider "aws" {
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "personal"
  region                  = var.aws_region
}

###############################################################################
# Blog resources.

data "aws_acm_certificate" "domain_cert" {
  domain      = var.domain
  statuses    = ["ISSUED"]
  most_recent = true
}

module "cdn" {
  source                   = "git::https://github.com/cloudposse/terraform-aws-cloudfront-s3-cdn.git?ref=tags/0.30.0"
  acm_certificate_arn      = data.aws_acm_certificate.domain_cert.arn
  namespace                = "basz"
  comment                  = "Bartek Szostek personal blog."
  stage                    = "production"
  name                     = "basz-blog"
  origin_force_destroy     = true
  compress                 = true
  ipv6_enabled             = true
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
  aliases = [
    var.domain,
  ]
  tags = {
    Environment = "production"
    Project     = "basz-personal-blog"
  }
}

# Block public access directly to the bucket.
resource "aws_s3_bucket_public_access_block" "origin_bucket_access_block" {
  bucket                  = module.cdn.s3_bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create Route53 entries pointing at CloudFront distribution.

data "aws_route53_zone" "selected" {
  name = var.domain
}

resource "aws_route53_record" "blog_ipv4" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = module.cdn.cf_domain_name
    zone_id                = module.cdn.cf_hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "blog_ipv6" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = var.domain
  type    = "AAAA"

  alias {
    name                   = module.cdn.cf_domain_name
    zone_id                = module.cdn.cf_hosted_zone_id
    evaluate_target_health = false
  }
}

###############################################################################
# Outputs.

output "origin_bucket_domain" {
  value = module.cdn.s3_bucket_domain_name
}
