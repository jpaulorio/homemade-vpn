data "aws_partition" "current" {}
data "aws_subnet" "public" {
  id = var.public_subnet_id
}
data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "exit" {
  name_prefix = "brazil-exit-"
  description = "No inbound ports; outbound Tailscale and SSM"
  vpc_id      = var.vpc_id
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_iam_role" "exit" {
  name_prefix = "brazil-exit-"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole"
  }] })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.exit.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "exit" {
  name_prefix = "brazil-exit-"
  role        = aws_iam_role.exit.name
}
resource "aws_instance" "exit" {
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.exit.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.exit.name
  user_data                   = file("${path.module}/bootstrap.sh")
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  volume_tags = { Project = "brazil-tailscale-exit", ManagedBy = "Terraform" }
  tags        = { Name = "brazil-tailscale-exit" }
  depends_on  = [aws_iam_role_policy_attachment.ssm]
  lifecycle {
    precondition {
      condition     = data.aws_subnet.public.vpc_id == var.vpc_id
      error_message = "Public subnet must belong to the selected VPC."
    }
  }
}
resource "aws_cognito_user_pool" "family" {
  name                     = "brazil-exit-family-users"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  user_pool_tier           = "LITE"
  admin_create_user_config {
    allow_admin_create_user_only = true
  }
  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }
}
resource "aws_cognito_user_pool_client" "mobile" {
  name                                 = "brazil-exit-flutter"
  user_pool_id                         = aws_cognito_user_pool.family.id
  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["brazilexit://oauth"]
  logout_urls                          = ["brazilexit://oauth"]
  refresh_token_validity               = 30
}
resource "aws_cognito_user_pool_domain" "mobile" {
  domain                = var.domain_prefix
  user_pool_id          = aws_cognito_user_pool.family.id
  managed_login_version = 1
}
resource "aws_iam_role" "control" {
  name_prefix = "brazil-control-"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole"
  }] })
}
resource "aws_iam_role_policy" "control" {
  role = aws_iam_role.control.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["ec2:DescribeInstances"], Resource = "*" },
    { Effect = "Allow", Action = ["ec2:StartInstances", "ec2:StopInstances"], Resource = aws_instance.exit.arn },
    { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.costs.arn}/current.json" },
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.control.arn}:*" }
  ] })
}
resource "aws_cloudwatch_log_group" "control" {
  name              = "/aws/lambda/brazil-exit-control-${var.domain_prefix}"
  retention_in_days = 14
}
data "archive_file" "control" {
  type        = "zip"
  source_file = "${path.module}/../aws/index.py"
  output_path = "${path.module}/control.zip"
}
resource "aws_lambda_function" "control" {
  function_name    = "brazil-exit-control-${var.domain_prefix}"
  role             = aws_iam_role.control.arn
  filename         = data.archive_file.control.output_path
  source_code_hash = data.archive_file.control.output_base64sha256
  runtime          = "python3.12"
  handler          = "index.handler"
  timeout          = 20
  memory_size      = 128
  environment {
    variables = { INSTANCE_ID = aws_instance.exit.id, COST_BUCKET = aws_s3_bucket.costs.id }
  }
  depends_on = [aws_iam_role_policy.control]
}
resource "aws_apigatewayv2_api" "control" {
  name          = "brazil-exit-control"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["https://${aws_cloudfront_distribution.web.domain_name}"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 300
  }
}
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.control.id
  authorizer_type  = "JWT"
  name             = "cognito-access-token"
  identity_sources = ["$request.header.Authorization"]
  jwt_configuration {
    issuer   = "https://cognito-idp.sa-east-1.amazonaws.com/${aws_cognito_user_pool.family.id}"
    audience = [aws_cognito_user_pool_client.mobile.id, aws_cognito_user_pool_client.web.id]
  }
}
resource "aws_apigatewayv2_integration" "control" {
  api_id                 = aws_apigatewayv2_api.control.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.control.invoke_arn
  payload_format_version = "2.0"
}
resource "aws_apigatewayv2_route" "control" {
  for_each             = toset(["GET /state", "POST /power", "GET /costs"])
  api_id               = aws_apigatewayv2_api.control.id
  route_key            = each.value
  target               = "integrations/${aws_apigatewayv2_integration.control.id}"
  authorization_type   = "JWT"
  authorizer_id        = aws_apigatewayv2_authorizer.cognito.id
  authorization_scopes = ["openid"]
}
resource "aws_apigatewayv2_stage" "control" {
  api_id      = aws_apigatewayv2_api.control.id
  name        = "$default"
  auto_deploy = true
  default_route_settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 5
  }
}
resource "aws_lambda_permission" "api" {
  statement_id  = "ApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.control.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.control.execution_arn}/*/*/*"
}
