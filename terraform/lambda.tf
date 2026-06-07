# ─────────────────────────────────────────────
#  Package Lambda source → zip
# ─────────────────────────────────────────────

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/src"
  output_path = "${path.module}/../lambda/lambda.zip"
}

# ─────────────────────────────────────────────
#  CloudWatch log group (explicit, for retention)
# ─────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days
}

# ─────────────────────────────────────────────
#  Lambda function
# ─────────────────────────────────────────────

resource "aws_lambda_function" "streaming" {
  function_name = "${var.project_name}-${var.environment}"
  description   = "Streaming token response demo — SSE via API Gateway REST"

  # Packaging
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Runtime — Node 22 supports ESM + awslambda.streamifyResponse natively
  runtime = "nodejs22.x"
  handler = "index.handler"

  # Resources
  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  # Execution role
  role = aws_iam_role.lambda_exec.arn

  # CloudWatch logging
  logging_config {
    log_group  = aws_cloudwatch_log_group.lambda_logs.name
    log_format = "JSON"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs,
  ]
}

# ─────────────────────────────────────────────
#  Permission — allow API Gateway to invoke Lambda
#  (uses InvokeWithResponseStream action under the hood)
# ─────────────────────────────────────────────

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.streaming.function_name
  principal     = "apigateway.amazonaws.com"

  # Restrict to this specific REST API
  source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}
