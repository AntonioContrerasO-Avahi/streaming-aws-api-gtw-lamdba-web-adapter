# ─────────────────────────────────────────────
#  Outputs
# ─────────────────────────────────────────────

output "api_invoke_url" {
  description = "Base URL of the deployed API Gateway stage"
  # In provider 6.x invoke_url lives on the STAGE resource (not deployment)
  value = aws_api_gateway_stage.prod.invoke_url
}

output "stream_endpoint" {
  description = "Full URL for the streaming POST endpoint"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/stream"
}

output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.streaming.function_name
}

output "lambda_function_arn" {
  description = "ARN of the deployed Lambda function"
  value       = aws_lambda_function.streaming.arn
}

output "lambda_response_streaming_invoke_arn" {
  description = "Streaming-specific invoke ARN (uses 2021-11-15 API + /response-streaming-invocations path)"
  value       = aws_lambda_function.streaming.response_streaming_invoke_arn
}

output "cloudwatch_log_group_lambda" {
  description = "CloudWatch log group for the Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "curl_test_command" {
  description = "Quick curl command to test the streaming endpoint"
  value       = <<-EOT
    curl -N -X POST \
      -H "Content-Type: application/json" \
      -d '{"prompt":"Tell me something interesting"}' \
      ${aws_api_gateway_stage.prod.invoke_url}/stream
  EOT
}
