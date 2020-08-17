---
title: "Terraforming Hugo blog"
date:  "2020-08-16"
tags: ["terraform", "aws", "hugo", "infrastructure"]
---

## Intro

Hosting a static content website on AWS is already a very simple task, especially for
people experienced in setting up cloud infrastructure. However, nobody wants to repeat
doing the boring stuff if it can be easily automated with existing tools.

I am using the following versions of software:

```sh
$ terraform --version
Terraform v0.12.28
$ aws --version
aws-cli/1.18.93 Python/3.8.3 Linux/5.7.7-arch1-1 botocore/1.17.16
$ hugo version
Hugo Static Site Generator v0.73.0/extended linux/amd64
```

## The problem

In my first post, I want to show how to automate the process of setting up a static
website behind a CDN, with TLS enabled for maximum security. I will explore how we can
achieve it using terraform on AWS cloud. To save some time, I will use the fastest
static website generator out there - [Hugo](https://gohugo.io/). I will also touch on some good
terraform and AWS practices as well as.

I want to automate the entire process on AWS, so there is a pre-requisite of having
a registered domain on Route53 DNS. Unfortunately, we can't automate the process of
purchasing a new domain (regardless of the size of our wallet), since domain names
can simply be not available or cost a lot of money.

Here is a list of tasks that we need to complete:

1. Create an ACM certificate, so that our website has that sweet `https://`.
2. Create a Route53 zone for our domain name.
3. Validate the certificate with our DNS name.
4. Create an S3 bucket, that will store our static files.
5. Spin-up a CloudFront distribution, with S3 bucket as origin and ACM cert.
6. Write DNS entries to point our domain at the CDN.

After completing all above tasks, the only thing left to do will be populating the bucket with some HTML files.

## A solution

### Using variables

To keep the solution generic and to allow reuse of the code in other projects,
it's recommended to parametrise the code with variables. Good candidates for
variables in terraform are settings like domain name and AWS region.
We can provide default values for variables in the code, or we can specify them
in a *terraform.tfvars* file. If terraform cannot find a value for our variable, it will
ask for it during planning phase. One more good advice: instead of writing
a comment in the tf file, use the `description` field of the variable.
Terraform will use it when prompting for the value.

```tf
variable "aws_region" {
  type        = string
  default     = "eu-west-1"
  description = "AWS default region."
}

variable "domain" {
  type        = string
  description = "Website domain name, without the protocol."
}
```

### Providing AWS access

Next, I have to define my [AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs). A provider is simply a client
module that allows terraform to provision resources in a desired cloud account.
In fact, I will configure two providers for the same account, with one simple
difference - region.

First provider is the default one, for most of our resources. As you can see, I didn't specify the region value directly in the file, but I used the variable
which I created earlier.

```tf
provider "aws" {
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "personal"
  region                  = var.aws_region
}
```

Second one is required for ACM certificate that will be used in CloudFront.
I aliased this provider as `cloudfront-acm-certs` to highlight its sole purpose.
If we dive into [AWS documentation](https://docs.aws.amazon.com/acm/latest/userguide/acm-services.html), we will notice the short note:

> To use an ACM certificate with CloudFront, you must request or import the certificate in the US East (N. Virginia) region.

```tf
provider "aws" {
  alias                   = "cloudfront-acm-certs"
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "personal"
  region                  = "us-east-1"
}
```

Both providers will look for AWS credentials in your [*~/.aws/credentials*](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html) file
and load the "personal" profile. This is handy if you often switch between
multiple accounts, like your company or client account versus your private one.

### Resource tagging strategy

Before we get to the core of the problem, I want to define some common tags
that will be assigned to all resources for my website. Tagging AWS resources
is an important detail, that's very often overlooked, but extremely helpful.
Having consistent tagging strategy allows for easy grouping of resources,
calculating cost of your projects, etc.

```tf
locals {
  common_tags = {
    Environment = "production"
    Project     = "personal-blog"
    Terraform   = "true"
  }
  namespace = lower(split(".", var.domain)[0])
}
```

### Certificate and hosted zone

Great, now I can get to the interesting stuff. First thing on my list was the [ACM certificate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate).
I have to specify the non-default provider, domain name and tags (recommended).
See how I used [`merge`](https://www.terraform.io/docs/configuration/functions/merge.html) function to add a custom `Name` tag.
An important detail is the validation method, which I set to `DNS`. This will help automate the validation step of this certificate; alternative method requires responding to an e-mail.
Setting the `create_before_destroy` lifecycle meta-argument will ensure
that if in the future I want to roll-over this cert via terraform,
it will create new one before the active one is destroyed.

```tf
resource "aws_acm_certificate" "cert" {
  provider          = aws.cloudfront-acm-certs

  domain_name       = var.domain
  validation_method = "DNS"

  tags = merge(local.common_tags, {Name = "${local.namespace}-cert"})

  lifecycle {
    create_before_destroy = true
  }
}
```

Next step requires creating a [Route53 hosted zone](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone). When purchasing a domain in Route53, AWS will create a default zone for you.
Since I want to terraform everything, I will set the `force_destroy`
to allow terraform creating a new one for me.

```tf
resource "aws_route53_zone" "primary" {
  name          = var.domain
  comment       = "Hosted zone for ${var.domain}"
  force_destroy = true

  tags = merge(local.common_tags, {Name = "${local.namespace}-zone"})
}
```

To validate my `cert` certificate, I have to create CNAME DNS records, which
can be exported directly from that resource. [`for_each`](https://www.terraform.io/docs/configuration/resources.html#for_each-multiple-resource-instances-defined-by-a-map-or-set-of-strings) allows me to easily iterate
over map of `domain_validation_options` and create multiple records if necessary.

```tf
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
```

DNS servers can be slow when propagating new changes, and there is not much
I can do to influence their nature. I need a way to "wait" for successful
validation of my certificate before I can use it in the next step.
To do that, I can use [`aws_acm_certificate_validation`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) resource. It may take a while to provision this
resource, so go grab a cup of tea and take your time.

```tf
resource "aws_acm_certificate_validation" "cert" {
  provider                = aws.cloudfront-acm-certs
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_records : record.fqdn]
}
```

### Delivering Content (almost)

Upon successful validation of my certificate, it's time to create origin S3 bucket and host its content using CloudFront.
Thankfully, it is such a common thing to do, that there is an external public
module that will provision and preconfigure most of the resources for me.

```tf
module "cdn" {
  source                   = "git::https://github.com/cloudposse/terraform-aws-cloudfront-s3-cdn.git?ref=tags/0.30.0"
  acm_certificate_arn      = aws_acm_certificate.cert.arn
  namespace                = local.namespace
  comment                  = "Personal blog"
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
}
```

You can see the full module documentation on its [GitHub page](https://github.com/cloudposse/terraform-aws-cloudfront-s3-cdn).
I will only go through the options which I customised or consider important:

- `origin_force_destroy` - allow terraform deleting the bucket.
- `compress` - CDN will gzip the content if client supports it.
- `logging_enabled` - I disabled logging, since I don't yet analyse my requests.
- `minimum_protocol_version` - I specified highest available TLS for max security.
  Some countries may block Internet traffic that uses cutting edge protocol version, so adjust it to your requirements.
- `custom_error_response` - my website has a custom error page for better user experience, so I have to tell CloudFront where to look for it.

It is also a good practice to ensure that any public access to our origin bucket is blocked.

```tf
resource "aws_s3_bucket_public_access_block" "origin_bucket_access_block" {
  bucket                  = module.cdn.s3_bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

### Redirecting domain

Final step is just a formality. I have to point my domain name to CDN distribution.
For that I have to create two [DNS alias records](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record#alias-record), one for IPv4 and one for IPv6 traffic.

The only difference between these records is their type. I also have to set the `evaluate_target_health`
property to `false`, since CloudFront distributions don't have health-checks.

```tf
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
```

### Clear outputs

Output log of a terraform plan/apply command can be extremely long, which makes finding
a name or ARN of a specific resource a challenging task. Obviously, I could login to AWS
console, navigate to specific resource page and search for what I need, but there is a better
approach.

In the case of my website, I need to know what's the name of S3 bucket so I can upload my content.
I can output the bucket domain name in the console by declaring an output variable.

```tf
output "origin_bucket_domain" {
  value       = module.cdn.s3_bucket_domain_name
  description = "S3 bucket for contents of the blog."
}
```

### Bonus - Resource group

AWS has a concept of Resource Groups, that allows users to aggregate all resources
that support tags in a single place. To create a group, only two things are required:
a group name, and a query consisting of list of tag names and their values.
Unsurprisingly, I can define a resource group using terraform.

```tf
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
```

There is no good syntax support for specifying `resource_query`, so I had to use "heredoc" syntax.

## Build & Deploy

To test the entire platform end-to-end, I have to upload some content to my S3 bucket.
With the following commands I can build my hugo website and upload it using AWS CLI:

```sh
HUGO_ENV=production hugo -v -s personal-blog -d ~/public
aws s3 sync ~/public s3://private-bucket-name/
```

## Summary

You can find the code for this project in my [GitHub repository](https://github.com/bartelemi/personal-blog).
