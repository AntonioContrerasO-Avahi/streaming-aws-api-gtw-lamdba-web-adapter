# Lambda Streaming v2 — Python / FastAPI / Docker / Terraform

Streams tokens through **API Gateway REST → Lambda (Docker image) → FastAPI + Lambda Web Adapter**.
No SAM. No zip files. Pure Terraform.

```
Client
  │  POST /stream  {"prompt": "..."}
  ▼
API Gateway REST  (REGIONAL, response_transfer_mode=STREAM)
  │
  ▼
Lambda  (Docker image, package_type=Image)
  │  Lambda Web Adapter extension (AWS_LWA_INVOKE_MODE=RESPONSE_STREAM)
  │  proxies HTTP ↔ Lambda runtime protocol
  ▼
FastAPI + uvicorn  (StreamingResponse, text/event-stream)
  │  yields SSE chunks word by word
  ▼
Client receives:
  data: {"token":"You "}
  data: {"token":"said: "}
  ...
  data: {"done":true}
```

---

## Project structure

```
streaming-v2/
├── app/
│   ├── Dockerfile          ← Python 3.12 + Lambda Web Adapter
│   ├── main.py             ← FastAPI app with fake_stream()
│   └── requirements.txt
├── terraform/
│   ├── versions.tf         ← aws + kreuzwerker/docker providers
│   ├── variables.tf
│   ├── ecr.tf              ← ECR repo + docker build + push
│   ├── iam.tf              ← Lambda role (+ Bedrock policy commented)
│   ├── lambda.tf           ← Docker image Lambda
│   ├── api_gateway.tf      ← REST API, STREAM integration, stage
│   └── outputs.tf
└── stream-chat.sh          ← bash terminal chat client (unchanged)
```

---

## Prerequisites

- Terraform >= 1.9 + AWS provider >= 6.41
- **Docker Desktop running locally** (kreuzwerker/docker builds the image on your machine)
- AWS credentials with ECR, Lambda, API Gateway, IAM permissions

---

## Deploy

```bash
cd terraform
terraform init
terraform apply
```

Terraform will:
1. Create an ECR repository
2. Build the Docker image locally (`docker build`)
3. Push it to ECR (`docker push`)
4. Create the Lambda function pointing at that image
5. Wire up API Gateway with `response_transfer_mode = "STREAM"`

---

## Test

```bash
# From terraform output:
terraform output -raw curl_test_command | bash

# Or manually (the -N flag stops curl buffering the stream):
curl -N -X POST \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Tell me something"}' \
  https://<api-id>.execute-api.<region>.amazonaws.com/dev/stream
```

### Terminal chat client

```bash
chmod +x stream-chat.sh
STREAM_URL=$(cd terraform && terraform output -raw stream_endpoint) ./stream-chat.sh
```

---

## Swap in real Bedrock

1. In `main.py` replace `fake_stream()` with the commented-out `bedrock_stream()`.
2. In `iam.tf` uncomment the `lambda_bedrock` policy attachment.
3. `terraform apply` — Terraform detects the source file change via `filesha256()`,
   rebuilds the image, pushes it, and updates the Lambda.

---

## Key Terraform concepts used

| Resource | What it does |
|---|---|
| `aws_ecr_repository` | Creates the container registry |
| `docker_image` | Builds the image locally via `docker build` |
| `docker_registry_image` | Pushes it to ECR via `docker push` |
| `aws_lambda_function` `package_type="Image"` | Docker-packaged Lambda (no zip/handler/runtime) |
| `aws_api_gateway_integration` `response_transfer_mode="STREAM"` | Enables streaming in API GW (provider 6.x) |
| `aws_lambda_function.response_streaming_invoke_arn` | Correct streaming URI without manual string hacks (provider 6.x) |
| `aws_api_gateway_account` | One-time account setting for CloudWatch logging |
