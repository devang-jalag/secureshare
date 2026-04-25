# Cognito User Pool
resource "aws_cognito_user_pool" "secure_share_users" {
  name = "${var.project_name}-users-${var.environment}"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "SecureShare — Verification Code"
    email_message        = "Your verification code is {####}."
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# App Client
# generate_secret is disabled because browser-based SPAs cannot securely store a client secret.
resource "aws_cognito_user_pool_client" "secure_share_client" {
  name         = "${var.project_name}-client"
  user_pool_id = aws_cognito_user_pool.secure_share_users.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]
}

# Outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.secure_share_users.id
  description = "Cognito User Pool ID"
}

output "cognito_client_id" {
  value       = aws_cognito_user_pool_client.secure_share_client.id
  description = "Cognito App Client ID"
}
