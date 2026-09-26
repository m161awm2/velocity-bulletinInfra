output "ecr_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "public_alb_dns_name" {
  value = aws_lb.public.dns_name
}

output "target_group_arn" {
  value = aws_lb_target_group.backend.arn
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.app.domain_name
}

output "media_bucket_name" {
  value = aws_s3_bucket.media.bucket
}

output "frontend_bucket_name" {
  value = aws_s3_bucket.frontend.bucket
}

output "app_secret_arn" {
  value = aws_secretsmanager_secret.app.arn
}

output "migration_secret_arn" {
  value = aws_secretsmanager_secret.migration.arn
}
