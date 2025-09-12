# Configure the AWS provider
provider "aws" {
  region = "us-east-1" # You can change this to your preferred region
}

# --- DynamoDB Table ---
# This is where we will store the form submissions.
resource "aws_dynamodb_table" "contact_table" {
  name           = "ContactFormSubmissions"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S" # S means String
  }
}

# --- IAM Role and Policy for Lambda ---
# This gives our Lambda function permission to write to DynamoDB and CloudWatch Logs.
resource "aws_iam_role" "lambda_exec_role" {
  name = "serverless_contact_form_role"
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

resource "aws_iam_policy" "lambda_policy" {
  name        = "serverless_contact_form_policy"
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
# First, we zip our Python source code.
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../src/"
  output_path = "${path.module}/lambda_function.zip"
}

# Now, we define the Lambda function itself.
resource "aws_lambda_function" "contact_form_lambda" {
  function_name    = "ContactFormHandler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  handler = "lambda_function.lambda_handler"
  runtime = "python3.9"
  role    = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.contact_table.name
    }
  }
}

# --- API Gateway (HTTP API v2) ---
# This creates the public URL.
resource "aws_apigatewayv2_api" "http_api" {
  name          = "ServerlessContactFormAPI"
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

# This permission allows API Gateway to invoke our Lambda function.
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
