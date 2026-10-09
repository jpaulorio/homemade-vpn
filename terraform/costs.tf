resource "aws_s3_bucket" "costs" {
  bucket_prefix = "brazil-exit-costs-"
}
resource "aws_s3_bucket_public_access_block" "costs" {
  bucket                  = aws_s3_bucket.costs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "costs" {
  bucket = aws_s3_bucket.costs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_iam_role" "costs" {
  name_prefix = "brazil-cost-report-"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole"
  }] })
}
resource "aws_cloudwatch_log_group" "costs" {
  name              = "/aws/lambda/brazil-exit-costs-${var.domain_prefix}"
  retention_in_days = 14
}
resource "aws_iam_role_policy" "costs" {
  role = aws_iam_role.costs.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["ce:GetCostAndUsage", "ce:ListCostAllocationTags", "ce:UpdateCostAllocationTagsStatus"], Resource = "*" },
    { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${aws_s3_bucket.costs.arn}/current.json" },
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.costs.arn}:*" }
  ] })
}
data "archive_file" "costs" {
  type        = "zip"
  source_file = "${path.module}/../aws/cost_report.py"
  output_path = "${path.module}/costs.zip"
}
resource "aws_lambda_function" "costs" {
  function_name    = "brazil-exit-costs-${var.domain_prefix}"
  role             = aws_iam_role.costs.arn
  filename         = data.archive_file.costs.output_path
  source_code_hash = data.archive_file.costs.output_base64sha256
  runtime          = "python3.12"
  handler          = "cost_report.handler"
  timeout          = 120
  memory_size      = 128
  environment {
    variables = { PROJECT_TAG = "brazil-tailscale-exit", COST_BUCKET = aws_s3_bucket.costs.id }
  }
  depends_on = [aws_iam_role_policy.costs]
}
resource "aws_cloudwatch_event_rule" "costs" {
  name                = "brazil-exit-daily-costs-${var.domain_prefix}"
  schedule_expression = "cron(0 12 * * ? *)"
}
resource "aws_cloudwatch_event_target" "costs" {
  rule      = aws_cloudwatch_event_rule.costs.name
  arn       = aws_lambda_function.costs.arn
  target_id = "daily-cost-report"
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 1
  }
}
resource "aws_lambda_permission" "costs" {
  statement_id  = "DailyCostReport"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.costs.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.costs.arn
}
output "cost_report_function" { value = aws_lambda_function.costs.function_name }
output "cost_report_bucket" { value = aws_s3_bucket.costs.id }
