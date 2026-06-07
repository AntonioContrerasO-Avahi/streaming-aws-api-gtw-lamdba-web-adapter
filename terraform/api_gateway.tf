# ─────────────────────────────────────────────
#  API Gateway Account — CloudWatch Logs role
#
#  This is a ONE-TIME, ACCOUNT-LEVEL setting.
#  API Gateway needs a role ARN registered here
#  before any stage can write logs to CloudWatch.
# ─────────────────────────────────────────────

data "aws_iam_policy_document" "apigw_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigw_cloudwatch" {
  name               = "${var.project_name}-${var.environment}-apigw-cw-role"
  assume_role_policy = data.aws_iam_policy_document.apigw_assume_role.json
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  role       = aws_iam_role.apigw_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch.arn

  depends_on = [aws_iam_role_policy_attachment.apigw_cloudwatch]
}

# ─────────────────────────────────────────────
#  API Gateway REST API
# ─────────────────────────────────────────────

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.project_name}-${var.environment}"
  description = "Streaming token REST API — response_transfer_mode STREAM"

  endpoint_configuration {
    # REGIONAL is required for streaming; EDGE (CloudFront) has a 30s idle timeout
    types = ["REGIONAL"]
  }
}

# ─────────────────────────────────────────────
#  Resource: /stream
# ─────────────────────────────────────────────

resource "aws_api_gateway_resource" "stream" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "stream"
}

# ─────────────────────────────────────────────
#  Method: POST /stream
# ─────────────────────────────────────────────

resource "aws_api_gateway_method" "post_stream" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.stream.id
  http_method   = "POST"
  authorization = "NONE" # swap to "AWS_IAM" or a Cognito authorizer in prod
}

# ─────────────────────────────────────────────
#  Integration — Lambda proxy with STREAM mode
#
#  Key fields added in aws provider 6.x:
#    • response_transfer_mode = "STREAM"
#    • uri = aws_lambda_function.streaming.response_streaming_invoke_arn
#            ↑ new attribute — no more manual string replace() hacks
#
#  The streaming URI looks like:
#    arn:aws:apigateway:<region>:lambda:path/2021-11-15/functions/<fn-arn>/response-streaming-invocations
# ─────────────────────────────────────────────

resource "aws_api_gateway_integration" "stream_lambda" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.stream.id
  http_method = aws_api_gateway_method.post_stream.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"

  # ✅ New in provider 6.x — purpose-built streaming invoke ARN
  uri = aws_lambda_function.streaming.response_streaming_invoke_arn

  # ✅ New in provider 6.x — enables STREAM transfer mode
  response_transfer_mode = "STREAM"

  # Set timeout to match (or less than) the Lambda timeout.
  # Max supported by API Gateway REST is 900 000 ms (15 min) for streaming.
  timeout_milliseconds = var.lambda_timeout_seconds * 1000
}

# ─────────────────────────────────────────────
#  CORS preflight: OPTIONS /stream
# ─────────────────────────────────────────────

resource "aws_api_gateway_method" "options_stream" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.stream.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_mock" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.stream.id
  http_method = aws_api_gateway_method.options_stream.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.stream.id
  http_method = aws_api_gateway_method.options_stream.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_mock_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.stream.id
  http_method = aws_api_gateway_method.options_stream.http_method
  status_code = aws_api_gateway_method_response.options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.options_mock]
}

# ─────────────────────────────────────────────
#  Deployment + Stage
#
#  In provider 6.x, invoke_url and execution_arn were moved OFF
#  aws_api_gateway_deployment and ONTO aws_api_gateway_stage.
#  stage_name is also removed from deployment — use stage resource.
# ─────────────────────────────────────────────

resource "aws_api_gateway_deployment" "deploy" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  # Force re-deploy when integration config changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.stream.id,
      aws_api_gateway_method.post_stream.id,
      aws_api_gateway_integration.stream_lambda.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deploy.id
  stage_name    = var.environment

  depends_on = [aws_api_gateway_account.main]

  # Access logging to CloudWatch
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }
}

resource "aws_cloudwatch_log_group" "apigw_logs" {
  name              = "/aws/apigateway/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days
}

# ─────────────────────────────────────────────
#  Method settings — enable detailed metrics
# ─────────────────────────────────────────────

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = true
    logging_level      = "INFO"
    data_trace_enabled = false # set true only for deep debugging (logs full req/resp)
  }
}
