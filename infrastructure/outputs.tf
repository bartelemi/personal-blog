###############################################################################
# Outputs.

# Website origin bucket domain name.
output "origin_bucket_domain" {
  value       = module.cdn.s3_bucket_domain_name
  description = "S3 bucket for contents of the blog. Upload all assets (HTML, CSS, JS) to the root of this bucket."
}

# Distribution address that hosts the website.
output "cdn_url" {
  value       = module.cdn.cf_domain_name
  description = "Distribution address. Create a DNS entry with this URL if not using Route53."
}
