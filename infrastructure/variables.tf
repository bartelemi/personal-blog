###############################################################################
# Variables.

variable "aws_region" {
  type        = string
  default     = "eu-west-1"
  description = "AWS default region."
}

variable "domain" {
  type        = string
  description = "Website domain name, without the protocol."
}

variable "cdn_comment" {
  type        = string
  default     = "Personal blog."
  description = "Comment describing CloudFront distribution."
}

locals {
  # Common tags to be assigned to all blog resources.
  common_tags = {
    Environment = "production"
    Project     = "personal-blog"
    Terraform   = "true"
  }
  namespace = lower(split(".", var.domain)[0])
}
