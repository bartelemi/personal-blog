###############################################################################
# Providers.

provider "aws" {
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "personal"
  region                  = var.aws_region
}

# Cloudfront ACM certs must exist in US N. Virginia (us-east-1) region.
provider "aws" {
  alias                   = "cloudfront-acm-certs"
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "personal"
  region                  = "us-east-1"
}
