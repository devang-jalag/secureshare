# API Gateway
resource "aws_apigatewayv2_api" "secure_share_api" {
  name          = "${var.project_name}-api-${var.environment}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 3000
  }
}

# Lambda Integrations
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.secure_share_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.presigned_url_generator.invoke_arn
  integration_method = "POST"
}

resource "aws_lambda_permission" "api_gw_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.presigned_url_generator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.secure_share_api.execution_arn}/*/*"
}

# JWT Authorizer
resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id           = aws_apigatewayv2_api.secure_share_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.project_name}-jwt-authorizer-${var.environment}"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.secure_share_client.id]
    issuer   = "https://${aws_cognito_user_pool.secure_share_users.endpoint}"
  }
}

# Routes
resource "aws_apigatewayv2_route" "generate_url_route" {
  api_id             = aws_apigatewayv2_api.secure_share_api.id
  route_key          = "POST /generate-url"
  target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.secure_share_api.id
  name        = "$default"
  auto_deploy = true
}

# List Files Route
resource "aws_apigatewayv2_integration" "list_files_integration" {
  api_id             = aws_apigatewayv2_api.secure_share_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.list_files.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "list_files_route" {
  api_id             = aws_apigatewayv2_api.secure_share_api.id
  route_key          = "GET /files"
  target             = "integrations/${aws_apigatewayv2_integration.list_files_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

resource "aws_lambda_permission" "api_gw_list_permission" {
  statement_id  = "AllowExecutionFromAPIGatewayList"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_files.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.secure_share_api.execution_arn}/*/*"
}

# Download URL Route (public — no JWT required)
resource "aws_apigatewayv2_integration" "download_integration" {
  api_id             = aws_apigatewayv2_api.secure_share_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.download_url.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "download_route" {
  api_id    = aws_apigatewayv2_api.secure_share_api.id
  route_key = "POST /download-url"
  target    = "integrations/${aws_apigatewayv2_integration.download_integration.id}"
}

resource "aws_lambda_permission" "api_gw_download_permission" {
  statement_id  = "AllowExecutionFromAPIGatewayDownload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.download_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.secure_share_api.execution_arn}/*/*"
}

# Outputs
output "api_endpoint" {
  value       = aws_apigatewayv2_api.secure_share_api.api_endpoint
  description = "Base API Gateway URL"
}
