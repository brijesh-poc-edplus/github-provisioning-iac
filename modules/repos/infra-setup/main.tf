provider "aws" {
  region = var.region

  assume_role {
    role_arn = var.role_arn
  }
}

resource "aws_s3_bucket" "frontend_bucket" {
  bucket = var.bucket_name
  lifecycle {
    ignore_changes = all
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  lifecycle {
    ignore_changes = all
  }
}

resource "aws_cloudfront_origin_access_control" "default" {
  name                              = "default-oac-${aws_s3_bucket.frontend_bucket.id}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
  lifecycle {
    ignore_changes = all
  }
}

locals {
  spa_error_responses = var.enable_spa_redirect ? [
    {
      error_code            = 404
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 0
    },
    {
      error_code            = 403
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 0
    }
  ] : []
}

resource "aws_cloudfront_distribution" "s3_distribution" {

  enabled = true

  origin {
    origin_id                = aws_s3_bucket.frontend_bucket.id
    domain_name              = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.frontend_bucket.id
    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  dynamic "custom_error_response" {
    for_each = local.spa_error_responses
    content {
      error_code            = custom_error_response.value.error_code
      response_code         = custom_error_response.value.response_code
      response_page_path    = custom_error_response.value.response_page_path
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
    }
  }

  default_root_object = var.enable_spa_redirect ? null : "index.html"

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  lifecycle {
    ignore_changes = all
  }

}

data "aws_iam_policy_document" "origin_bucket_policy" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.frontend_bucket.arn}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.s3_distribution.arn]
    }
  }
}


resource "aws_s3_bucket_policy" "frontend_bucket_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = data.aws_iam_policy_document.origin_bucket_policy.json
  lifecycle {
    ignore_changes = all
  }
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  count  = var.enable_spa_redirect ? 1 : 0
  bucket = var.bucket_name
  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "index.html"
  }
  lifecycle {
    ignore_changes = all
  }
}

resource "aws_acm_certificate" "cert" {

  count = var.issue_custom_domain_cert ? 1 : 0
  domain_name       = var.custom_domain_name
  validation_method = "DNS"

  tags = {
    CREATED_BY = "terraform"
  }

  lifecycle {
    create_before_destroy = true
  }

}