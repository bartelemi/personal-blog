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
  compress                 = true
  ipv6_enabled             = true
  logging_enabled          = false
  minimum_protocol_version = "TLSv1.2_2018"
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

###############################################################################
# Outputs.

output "origin_bucket_domain" {
  value = module.cdn.s3_bucket_domain_name
}
