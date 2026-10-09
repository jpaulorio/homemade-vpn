data "aws_cloudfront_cache_policy" "disabled" { name = "Managed-CachingDisabled" }
resource "aws_s3_bucket" "web" {
  bucket_prefix = "brazil-exit-controller-"
}
resource "aws_s3_bucket_public_access_block" "web" {
  bucket                  = aws_s3_bucket.web.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "web" {
  bucket = aws_s3_bucket.web.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_cloudfront_origin_access_control" "web" {
  name                              = "${var.domain_prefix}-web"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
resource "aws_cloudfront_response_headers_policy" "web" {
  name = "${var.domain_prefix}-web-security"
  security_headers_config {
    content_type_options { override = true }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "no-referrer"
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      override                   = true
    }
    content_security_policy {
      content_security_policy = "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self' https://*.execute-api.sa-east-1.amazonaws.com https://${var.domain_prefix}.auth.sa-east-1.amazoncognito.com; frame-ancestors 'none'; base-uri 'none'; object-src 'none'"
      override                = true
    }
  }
}
resource "aws_cloudfront_distribution" "web" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  origin {
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_id                = "controller"
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }
  default_cache_behavior {
    target_origin_id           = "controller"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.web.id
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate { cloudfront_default_certificate = true }
}
resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { Service = "cloudfront.amazonaws.com" }, Action = "s3:GetObject", Resource = "${aws_s3_bucket.web.arn}/*",
    Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.web.arn } }
  }] })
}
resource "aws_cognito_user_pool_client" "web" {
  name                                 = "brazil-exit-browser"
  user_pool_id                         = aws_cognito_user_pool.family.id
  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://${aws_cloudfront_distribution.web.domain_name}/"]
  logout_urls                          = ["https://${aws_cloudfront_distribution.web.domain_name}/"]
  access_token_validity                = 60
  token_validity_units { access_token = "minutes" }
}
resource "aws_s3_object" "web" {
  for_each      = { "index.html" = "text/html", "app.js" = "text/javascript", "style.css" = "text/css" }
  bucket        = aws_s3_bucket.web.id
  key           = each.key
  source        = "${path.module}/../web/${each.key}"
  source_hash   = filemd5("${path.module}/../web/${each.key}")
  content_type  = each.value
  cache_control = "no-store"
}
resource "aws_s3_object" "web_config" {
  bucket        = aws_s3_bucket.web.id
  key           = "config.json"
  content_type  = "application/json"
  cache_control = "no-store"
  content       = jsonencode({ api = aws_apigatewayv2_api.control.api_endpoint, clientId = aws_cognito_user_pool_client.web.id, domain = "https://${var.domain_prefix}.auth.sa-east-1.amazoncognito.com" })
}
output "browser_url" { value = "https://${aws_cloudfront_distribution.web.domain_name}/" }
