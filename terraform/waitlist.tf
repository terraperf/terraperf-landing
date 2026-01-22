# TerraPerf Waitlist API Infrastructure
# Lambda + API Gateway + DynamoDB

# DynamoDB table for waitlist emails
resource "aws_dynamodb_table" "waitlist" {
  name         = "${var.project_name}-waitlist-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "email"

  attribute {
    name = "email"
    type = "S"
  }

  tags = {
    Name        = "TerraPerf Waitlist"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM role for Lambda
resource "aws_iam_role" "waitlist_lambda" {
  name = "${var.project_name}-waitlist-lambda-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "TerraPerf Waitlist Lambda Role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM policy for Lambda
resource "aws_iam_role_policy" "waitlist_lambda" {
  name = "${var.project_name}-waitlist-lambda-policy-${var.environment}"
  role = aws_iam_role.waitlist_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.waitlist.arn
      }
    ]
  })
}

# Lambda function
resource "aws_lambda_function" "waitlist" {
  function_name = "${var.project_name}-waitlist-${var.environment}"
  role          = aws_iam_role.waitlist_lambda.arn
  handler       = "lambda_handler.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.waitlist_lambda.output_path
  source_code_hash = data.archive_file.waitlist_lambda.output_base64sha256

  environment {
    variables = {
      WAITLIST_TABLE = aws_dynamodb_table.waitlist.name
      ENVIRONMENT    = var.environment
      CORS_ORIGINS   = "https://terraperf.com,https://www.terraperf.com"
    }
  }

  tags = {
    Name        = "TerraPerf Waitlist API"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Package Lambda code
data "archive_file" "waitlist_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../api/lambda"
  output_path = "${path.module}/waitlist_lambda.zip"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "waitlist_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.waitlist.function_name}"
  retention_in_days = 14

  tags = {
    Name        = "TerraPerf Waitlist Logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Gateway HTTP API
resource "aws_apigatewayv2_api" "waitlist" {
  name          = "${var.project_name}-waitlist-${var.environment}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["https://terraperf.com", "https://www.terraperf.com"]
    allow_methods = ["GET", "POST", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  tags = {
    Name        = "TerraPerf Waitlist API Gateway"
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Gateway stage
resource "aws_apigatewayv2_stage" "waitlist" {
  api_id      = aws_apigatewayv2_api.waitlist.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.waitlist_api.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
    })
  }

  tags = {
    Name        = "TerraPerf Waitlist API Stage"
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "waitlist_api" {
  name              = "/aws/apigateway/${var.project_name}-waitlist-${var.environment}"
  retention_in_days = 14

  tags = {
    Name        = "TerraPerf Waitlist API Logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Gateway Lambda integration
resource "aws_apigatewayv2_integration" "waitlist" {
  api_id                 = aws_apigatewayv2_api.waitlist.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.waitlist.invoke_arn
  payload_format_version = "2.0"
}

# API Gateway routes
resource "aws_apigatewayv2_route" "waitlist_get" {
  api_id    = aws_apigatewayv2_api.waitlist.id
  route_key = "GET /waitlist"
  target    = "integrations/${aws_apigatewayv2_integration.waitlist.id}"
}

resource "aws_apigatewayv2_route" "waitlist_post" {
  api_id    = aws_apigatewayv2_api.waitlist.id
  route_key = "POST /waitlist"
  target    = "integrations/${aws_apigatewayv2_integration.waitlist.id}"
}

resource "aws_apigatewayv2_route" "waitlist_delete" {
  api_id    = aws_apigatewayv2_api.waitlist.id
  route_key = "DELETE /waitlist/{email}"
  target    = "integrations/${aws_apigatewayv2_integration.waitlist.id}"
}

resource "aws_apigatewayv2_route" "waitlist_root" {
  api_id    = aws_apigatewayv2_api.waitlist.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.waitlist.id}"
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "waitlist_api" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.waitlist.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.waitlist.execution_arn}/*/*"
}

# Regional ACM certificate for API Gateway (must be in same region as API Gateway)
resource "aws_acm_certificate" "api" {
  domain_name       = "api.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "TerraPerf API Certificate"
    Environment = var.environment
    Project     = var.project_name
  }
}

# DNS validation for API certificate
resource "aws_route53_record" "api_acm_validation" {
  provider = aws.route53
  for_each = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
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

# Wait for API certificate validation
resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for record in aws_route53_record.api_acm_validation : record.fqdn]
}

# Custom domain for API (uses api.terraperf.com)
resource "aws_apigatewayv2_domain_name" "waitlist" {
  domain_name = "api.${var.domain_name}"

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.api.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = {
    Name        = "TerraPerf Waitlist API Domain"
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Gateway domain mapping
resource "aws_apigatewayv2_api_mapping" "waitlist" {
  api_id      = aws_apigatewayv2_api.waitlist.id
  domain_name = aws_apigatewayv2_domain_name.waitlist.id
  stage       = aws_apigatewayv2_stage.waitlist.id
}

# Route53 record for API
resource "aws_route53_record" "api" {
  provider = aws.route53
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = "api.${var.domain_name}"
  type     = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.waitlist.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.waitlist.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# Outputs
output "waitlist_api_endpoint" {
  value       = aws_apigatewayv2_api.waitlist.api_endpoint
  description = "Waitlist API Gateway endpoint"
}

output "waitlist_api_domain" {
  value       = "https://api.${var.domain_name}"
  description = "Waitlist API custom domain"
}

output "waitlist_dynamodb_table" {
  value       = aws_dynamodb_table.waitlist.name
  description = "Waitlist DynamoDB table name"
}
