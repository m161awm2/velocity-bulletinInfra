mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:loadbalancer/app/test/1234567890123456"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:targetgroup/test/1234567890123456"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/test"
    }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = {
      arn = "arn:aws:ecs:ap-northeast-2:123456789012:task-definition/test:1"
    }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = {
      arn = "arn:aws:ecs:ap-northeast-2:123456789012:cluster/test"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}
mock_provider "random" {}

variables {
  database_url           = "postgresql://test:test@db-pooler.example.invalid/app?sslmode=require"
  migration_database_url = "postgresql://test:test@db.example.invalid/app?sslmode=require"
  backend_image          = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/backend:test"
}

run "public_alb_private_tasks" {
  command = apply

  assert {
    condition     = aws_lb.public.internal == false && aws_lb.public.subnets == toset(aws_subnet.public[*].id)
    error_message = "The internet-facing ALB must use the public subnets."
  }
  assert {
    condition     = aws_ecs_service.backend.network_configuration[0].assign_public_ip == false && aws_ecs_service.backend.network_configuration[0].subnets == toset(aws_subnet.private_app[*].id)
    error_message = "ECS tasks must remain in private subnets without public IPs."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.alb_from_cloudfront.prefix_list_id == data.aws_ec2_managed_prefix_list.cloudfront.id && aws_vpc_security_group_ingress_rule.alb_from_cloudfront.from_port == 80
    error_message = "Only CloudFront origin-facing HTTP traffic should enter the ALB."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.task_from_alb.referenced_security_group_id == aws_security_group.alb.id && aws_vpc_security_group_ingress_rule.task_from_alb.from_port == var.container_port
    error_message = "The backend must accept application traffic from the ALB SG."
  }
  assert {
    condition     = one([for origin in aws_cloudfront_distribution.app.origin : origin if origin.origin_id == "public-alb"]).domain_name == aws_lb.public.dns_name
    error_message = "CloudFront must use the public ALB DNS as its API origin."
  }
  assert {
    condition     = aws_cloudfront_distribution.app.ordered_cache_behavior[0].target_origin_id == "public-alb" && aws_cloudfront_distribution.app.ordered_cache_behavior[0].cache_policy_id == data.aws_cloudfront_cache_policy.caching_disabled.id && aws_cloudfront_distribution.app.ordered_cache_behavior[0].origin_request_policy_id == data.aws_cloudfront_origin_request_policy.api.id
    error_message = "API traffic must use the public ALB with caching disabled and Authorization forwarding."
  }
}
