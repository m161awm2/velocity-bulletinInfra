variable "aws_region" {
  description = "Workload region. Seoul is required for the 2-AZ layout described in the README."
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "Short project name used as a prefix for resource names."
  type        = string
  default     = "velocity"
}

variable "azs" {
  description = "The two availability zones the network and Fargate service are spread across."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "vpc_cidr" {
  description = "VPC CIDR block. Must be large enough to hold two /24 public and two /24 private subnets."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per AZ (NAT Gateway only, no inbound internet routes to workloads)."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "Private application subnet CIDRs, one per AZ (ECS tasks, internal ALB, CloudFront VPC Origin ENIs)."
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

variable "container_port" {
  description = "Port the backend container listens on."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "HTTP path the ALB target group uses for health checks."
  type        = string
  default     = "/health/ready"
}

variable "ecs_task_cpu" {
  type    = string
  default = "256"
}

variable "ecs_task_memory" {
  type    = string
  default = "512"
}

variable "ecs_desired_count" {
  type    = number
  default = 2
}

variable "cloudfront_vpc_origin_managed_sg_id" {
  description = <<-EOT
    Security group ID that AWS auto-creates for the CloudFront VPC Origin
    once it's associated with a distribution. Unknown (and unsettable)
    on a from-scratch apply - leave null for the first apply, then fill
    it in and re-apply. See alb.tf for the full sequence.
  EOT
  type        = string
  default     = null
}

variable "backend_image" {
  description = "Full ECR image URI (repo:tag) deployed to the ECS task definition. Overridden per-deploy by CI with the Git SHA tag."
  type        = string
  default     = "" # populated by CI (`<ecr_repo_url>:<git-sha>`); required at apply time otherwise
}

# --- Secrets -----------------------------------------------------------
# Real values are never committed. Supply them via a git-ignored *.tfvars
# file, CI-injected -var, or TF_VAR_* environment variables.

variable "database_url" {
  description = "Neon pooled Postgres connection string used by the running application (DATABASE_URL)."
  type        = string
  sensitive   = true
}

variable "migration_database_url" {
  description = "Neon *unpooled* (direct) Postgres connection string, used only by the one-off migration task."
  type        = string
  sensitive   = true
}
