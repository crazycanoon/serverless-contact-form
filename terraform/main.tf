# Configure the AWS provider
provider "aws" {
  region = "us-east-1"
}

# --- Unique Suffix Generator ---
# This is the key to our solution. It creates a random, memorable suffix.
resource "random_pet" "suffix" {
  length = 2
}

# --- Local variable for easy use of the suffix ---
locals {
  # We combine a project prefix with the random pet name for clarity.
  # Example output: "scontact-witty-walrus"
  unique_suffix = "scontact-${random_pet.suffix.id}"
}


# --- DynamoDB Table ---
# The table name now includes our unique suffix.
resource "aws_dynamodb_table" "contact_table" {
  name           = "ContactFormSubmissions-${local.unique_suffix}" # <-- MODIFIED
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# --- IAM Role and Policy for Lambda ---
# The IAM role name is now unique.
resource "aws_iam_role" "lambda_exec_role" {
  name = "${local.unique_suffix}-lambda-role" # <-- MODIFIED
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# The IAM policy name is now unique.
resource "aws_iam_policy" "lambda_policy" {
  name        = "${local.unique_suffix}-lambda-policy" # <-- MODIFIED
  description = "IAM policy for Lambda to access DynamoDB and CloudWatch"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action   = ["dynamodb:PutItem"]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.contact_table.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# --- Lambda Function ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../src/"
  output_path = "${path.module}/lambda_function.zip"
}

# The Lambda function name is now unique.
resource "aws_lambda_function" "contact_form_lambda" {
  function_name    = "ContactFormHandler-${local.unique_suffix}" # <-- MODIFIED
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  handler = "lambda_function.lambda_handler"
  runtime = "python3.9"
  role    = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      # Pass the unique table name to the Lambda function
      TABLE_NAME = aws_dynamodb_table.contact_table.name # <-- MODIFIED
    }
  }
}

# --- API Gateway (HTTP API v2) ---
# The API Gateway name is now unique.
resource "aws_apigatewayv2_api" "http_api" {
  name          = "ServerlessContactFormAPI-${local.unique_suffix}" # <-- MODIFIED
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.contact_form_lambda.invoke_arn
}

resource "aws_apigatewayv2_route" "submit_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /submit"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayToInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contact_form_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# --- Outputs ---
# This will print the API Gateway URL after deployment.
output "api_endpoint" {
  description = "The invoke URL for the API Gateway."
  value       = aws_apigatewayv2_stage.default_stage.invoke_url
}

