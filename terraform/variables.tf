variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used for all resources"
  type        = string
  default     = "lambda-streaming"
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
  default     = "dev"
}

variable "lambda_memory_mb" {
  description = "Lambda memory in MB (128–10240)"
  type        = number
  default     = 512
}

variable "lambda_timeout_seconds" {
  description = <<-EOT
    Lambda execution timeout in seconds.
    For streaming / LLM workloads raise this to 300–900.
    API Gateway integration timeout is set to match (up to 900 s).
  EOT
  type        = number
  default     = 60
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 7
}
