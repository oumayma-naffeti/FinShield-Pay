
data "aws_s3_bucket" "site" {
  bucket = var.bucket_name
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project}-frontend"
  retention_in_days = 7
}

resource "aws_lambda_function" "frontend" {
  function_name = "${var.project}-frontend"
  role          = var.execution_role_arn
  handler       = "index.handler"
  runtime       = "python3.12"
  filename      = var.lambda_zip_path

  source_code_hash = filebase64sha256(var.lambda_zip_path)

  timeout     = 10
  memory_size = 128

  environment {
    variables = {
      BUCKET_NAME = data.aws_s3_bucket.site.bucket
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda
  ]

  tags = {
    Name = "${var.project}-frontend"
  }
}

resource "aws_api_gateway_rest_api" "frontend" {
  name = "${var.project}-frontend"

  binary_media_types = [
    "image/*",
    "font/*",
    "application/octet-stream"
  ]

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${var.project}-frontend"
  }
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.frontend.id
  parent_id   = aws_api_gateway_rest_api.frontend.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "root" {
  rest_api_id   = aws_api_gateway_rest_api.frontend.id
  resource_id   = aws_api_gateway_rest_api.frontend.root_resource_id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.frontend.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "root" {
  rest_api_id             = aws_api_gateway_rest_api.frontend.id
  resource_id             = aws_api_gateway_rest_api.frontend.root_resource_id
  http_method             = aws_api_gateway_method.root.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.frontend.invoke_arn
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.frontend.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.frontend.invoke_arn
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowFrontendApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.frontend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.frontend.execution_arn}/*/GET*"
}

resource "aws_api_gateway_deployment" "frontend" {
  rest_api_id = aws_api_gateway_rest_api.frontend.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.root.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_integration.root.id,
      aws_api_gateway_integration.proxy.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.root,
    aws_api_gateway_integration.proxy
  ]
}

resource "aws_api_gateway_stage" "frontend" {
  rest_api_id   = aws_api_gateway_rest_api.frontend.id
  deployment_id = aws_api_gateway_deployment.frontend.id
  stage_name    = var.stage_name
}

resource "aws_wafv2_web_acl_association" "frontend" {
  resource_arn = aws_api_gateway_stage.frontend.arn
  web_acl_arn  = var.web_acl_arn
}



