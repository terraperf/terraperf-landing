# Lambda@Edge for Basic Authentication on Landing Page
# Note: Lambda@Edge functions MUST be created in us-east-1 region

# Generate the Basic Auth Lambda code from template
resource "local_file" "basic_auth_js" {
  count    = var.basic_auth_enabled ? 1 : 0
  filename = "${path.module}/basic_auth.js"
  content = templatefile("${path.module}/basic_auth.js.tpl", {
    credentials_base64 = base64encode("${var.basic_auth_username}:${var.basic_auth_password}")
    realm              = "TerraPerf Preview - Protected Area"
    username           = var.basic_auth_username
    password           = var.basic_auth_password
  })
}

# IAM role for Lambda@Edge
resource "aws_iam_role" "lambda_edge" {
  count    = var.basic_auth_enabled ? 1 : 0
  provider = aws.us_east_1
  name     = "terraperf-landing-basic-auth"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "edgelambda.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = {
    Name        = "TerraPerf Landing Basic Auth Lambda@Edge Role"
    Environment = var.environment
    Project     = "terraperf"
  }
}

# Attach basic execution role for CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_edge_logs" {
  count      = var.basic_auth_enabled ? 1 : 0
  provider   = aws.us_east_1
  role       = aws_iam_role.lambda_edge[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Archive the Lambda function code
data "archive_file" "basic_auth" {
  count       = var.basic_auth_enabled ? 1 : 0
  type        = "zip"
  source_file = local_file.basic_auth_js[0].filename
  output_path = "${path.module}/basic_auth.zip"

  depends_on = [local_file.basic_auth_js]
}

# Lambda@Edge function for Basic Authentication
resource "aws_lambda_function" "basic_auth" {
  count            = var.basic_auth_enabled ? 1 : 0
  provider         = aws.us_east_1
  filename         = data.archive_file.basic_auth[0].output_path
  function_name    = "terraperf-landing-basic-auth"
  role             = aws_iam_role.lambda_edge[0].arn
  handler          = "basic_auth.handler"
  source_code_hash = data.archive_file.basic_auth[0].output_base64sha256
  runtime          = "nodejs20.x"
  timeout          = 5
  memory_size      = 128
  publish          = true # Required for Lambda@Edge

  tags = {
    Name        = "TerraPerf Landing Basic Auth"
    Environment = var.environment
    Project     = "terraperf"
  }
}

# Outputs
output "basic_auth_lambda_arn" {
  description = "Lambda@Edge function ARN with version"
  value       = var.basic_auth_enabled ? aws_lambda_function.basic_auth[0].qualified_arn : null
}

output "basic_auth_enabled" {
  description = "Whether Basic Auth is enabled"
  value       = var.basic_auth_enabled
}
