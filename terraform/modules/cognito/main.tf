data "aws_caller_identity" "me" {}

resource "aws_cognito_user_pool" "main" {
  name                     = "${var.project}-users"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  tags = { Name = "${var.project}-users" }
}

resource "aws_cognito_user_pool_client" "portal" {
  name         = "${var.project}-portal"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = false
  explicit_auth_flows                  = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls
  prevent_user_existence_errors        = "ENABLED"
}

# Hosted UI : le prefixe de domaine doit etre unique dans la region
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project}-${data.aws_caller_identity.me.account_id}"
  user_pool_id = aws_cognito_user_pool.main.id
}