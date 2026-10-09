output "instance_id" { value = aws_instance.exit.id }
output "user_pool_id" { value = aws_cognito_user_pool.family.id }
output "cognito_domain" { value = "https://${var.domain_prefix}.auth.sa-east-1.amazoncognito.com" }
output "flutter_config" {
  value = {
    API_BASE_URL      = aws_apigatewayv2_api.control.api_endpoint
    COGNITO_ISSUER    = "https://cognito-idp.sa-east-1.amazonaws.com/${aws_cognito_user_pool.family.id}"
    COGNITO_CLIENT_ID = aws_cognito_user_pool_client.mobile.id
  }
}
