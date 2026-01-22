terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "terraperf-terraform-state-prod"
    key            = "terraperf-landing/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraperf-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# Provider for ACM certificate (must be us-east-1 for CloudFront)
provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = var.aws_profile
}

# Provider for Route53 (in shared services account)
provider "aws" {
  alias   = "route53"
  region  = "eu-west-1"
  profile = "terraperf-core-sharedservices"
}

# Route53 hosted zone (in shared services account)
data "aws_route53_zone" "main" {
  provider = aws.route53
  name     = var.domain_name
}

# S3 bucket for static website hosting
resource "aws_s3_bucket" "landing" {
  bucket = var.bucket_name

  tags = {
    Name        = "TerraPerf Landing Page"
    Environment = "production"
    Project     = "terraperf"
  }
}

# Block all public access (CloudFront will access via OAC)
resource "aws_s3_bucket_public_access_block" "landing" {
  bucket = aws_s3_bucket.landing.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for CloudFront OAC
resource "aws_s3_bucket_policy" "landing" {
  bucket = aws_s3_bucket.landing.id
  policy = data.aws_iam_policy_document.s3_policy.json
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.landing.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.landing.arn]
    }
  }
}

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "landing" {
  name                              = "terraperf-landing-oac"
  description                       = "OAC for TerraPerf Landing Page"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ACM Certificate for terraperf.com (must be in us-east-1 for CloudFront)
resource "aws_acm_certificate" "landing" {
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"

  subject_alternative_names = [
    "www.${var.domain_name}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "TerraPerf Landing Certificate"
    Environment = "production"
    Project     = "terraperf"
  }
}

# ACM certificate DNS validation records (in Route53)
resource "aws_route53_record" "acm_validation" {
  provider = aws.route53
  for_each = {
    for dvo in aws_acm_certificate.landing.domain_validation_options : dvo.domain_name => {
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
  zone_id         = data.aws_route53_zone.main.zone_id
}

# Wait for ACM certificate validation
resource "aws_acm_certificate_validation" "landing" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.landing.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

# Route53 A record for apex domain
resource "aws_route53_record" "apex" {
  provider = aws.route53
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = var.domain_name
  type     = "A"

  alias {
    name                   = aws_cloudfront_distribution.landing.domain_name
    zone_id                = aws_cloudfront_distribution.landing.hosted_zone_id
    evaluate_target_health = false
  }
}

# Route53 A record for www subdomain
resource "aws_route53_record" "www" {
  provider = aws.route53
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = "www.${var.domain_name}"
  type     = "A"

  alias {
    name                   = aws_cloudfront_distribution.landing.domain_name
    zone_id                = aws_cloudfront_distribution.landing.hosted_zone_id
    evaluate_target_health = false
  }
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "landing" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain_name, "www.${var.domain_name}"]
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.landing.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.landing.bucket}"
    origin_access_control_id = aws_cloudfront_origin_access_control.landing.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.landing.bucket}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # Custom error response for SPA routing
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.landing.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name        = "TerraPerf Landing Distribution"
    Environment = "production"
    Project     = "terraperf"
  }
}

# Outputs
output "s3_bucket_name" {
  value       = aws_s3_bucket.landing.bucket
  description = "S3 bucket name for deployment"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.landing.id
  description = "CloudFront distribution ID for cache invalidation"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.landing.domain_name
  description = "CloudFront domain name"
}

output "acm_certificate_arn" {
  value       = aws_acm_certificate.landing.arn
  description = "ACM certificate ARN"
}

output "acm_validation_records" {
  value = {
    for dvo in aws_acm_certificate.landing.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
  description = "DNS records needed for ACM certificate validation"
}
