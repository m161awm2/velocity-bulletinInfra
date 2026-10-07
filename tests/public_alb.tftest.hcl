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
  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:listener/app/test/1234567890123456/1234567890123456"
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
mock_provider "random" {
  mock_resource "random_password" {
    defaults = {
      result = "cloudfront-origin-verification"
    }
  }
}

variables {
  database_url  = "postgresql://test:test@db-pooler.example.invalid/app?sslmode=require"
  backend_image = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/backend:test"
}

run "public_alb_private_tasks" {
  command = apply

  assert {
    condition     = one(jsondecode(aws_ecs_task_definition.migrate.container_definitions)[0].secrets).valueFrom == "${aws_secretsmanager_secret.app.arn}:DATABASE_URL::"
    error_message = "The migration task must use the same pooled database URL secret as the backend."
  }

  assert {
    condition     = length(aws_nat_gateway.main) == 1 && aws_nat_gateway.main[0].subnet_id == aws_subnet.public[0].id
    error_message = "The console-built network uses one NAT Gateway in the first public subnet."
  }
  assert {
    condition     = length(aws_route_table.private_app) == 1 && alltrue([for association in aws_route_table_association.private_app : association.route_table_id == aws_route_table.private_app[0].id])
    error_message = "Both private application subnets must use the shared private route table."
  }
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
    condition     = one(one([for origin in aws_cloudfront_distribution.app.origin : origin if origin.origin_id == "public-alb"]).custom_header).name == "X-Origin-Verify"
    error_message = "CloudFront must add the origin verification header to ALB requests."
  }
  assert {
    condition     = aws_lb_listener.public_http.default_action[0].type == "fixed-response" && aws_lb_listener.public_http.default_action[0].fixed_response[0].status_code == "403"
    error_message = "The ALB must reject requests that do not contain the origin verification header."
  }
  assert {
    condition     = aws_lb_listener_rule.cloudfront_only.action[0].target_group_arn == aws_lb_target_group.backend.arn && one(aws_lb_listener_rule.cloudfront_only.condition).http_header[0].http_header_name == "X-Origin-Verify" && nonsensitive(one(one(aws_lb_listener_rule.cloudfront_only.condition).http_header[0].values)) == nonsensitive(one(one([for origin in aws_cloudfront_distribution.app.origin : origin if origin.origin_id == "public-alb"]).custom_header).value)
    error_message = "Only requests with CloudFront's origin verification header should reach the backend target group."
  }
  assert {
    condition     = aws_cloudfront_distribution.app.ordered_cache_behavior[0].target_origin_id == "public-alb" && aws_cloudfront_distribution.app.ordered_cache_behavior[0].cache_policy_id == data.aws_cloudfront_cache_policy.caching_disabled.id && aws_cloudfront_distribution.app.ordered_cache_behavior[0].origin_request_policy_id == data.aws_cloudfront_origin_request_policy.api.id
    error_message = "API traffic must use the public ALB with caching disabled and Authorization forwarding."
  }
  assert {
    condition     = data.aws_cloudfront_origin_request_policy.api.name == "Managed-AllViewer"
    error_message = "The API behavior must forward the viewer request settings selected in CloudFront."
  }
}
