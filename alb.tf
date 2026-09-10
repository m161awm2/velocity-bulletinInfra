# Security group chain (matches README "Security Group 흐름"):
#
#   CloudFront VPC Origin managed SG
#       -> alb sg: port 80
#            -> task sg: TCP 8080
#
# AWS auto-creates the VPC Origin's service-managed SG only *after* the
# VPC Origin in cloudfront.tf is associated with a live distribution -
# it does not exist at the time this SG is first created, so its ID
# cannot be referenced as a normal resource attribute. This is the same
# ordering problem hit doing this by hand in the console ("배포가 되면
# 자동으로 보안그룹이 생기는데 이터널 ALB 인바운드 보안그룹에 넣어주겠다"):
#   1. `terraform apply` once with var.cloudfront_vpc_origin_managed_sg_id
#      left null - everything is created except this one ingress rule.
#   2. Look up the SG AWS created for the VPC Origin
#      (`aws ec2 describe-security-groups` filtered on the VPC, or the
#      CloudFront console's VPC Origins detail page).
#   3. `terraform apply -var="cloudfront_vpc_origin_managed_sg_id=sg-..."`
#      (or set it in *.tfvars) to add the rule.
resource "aws_security_group" "alb" {
  name        = "${var.project}-alb-sg"
  description = "${var.project}-alb-sg"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_vpc_origin" {
  count                        = var.cloudfront_vpc_origin_managed_sg_id != null ? 1 : 0
  security_group_id            = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = var.cloudfront_vpc_origin_managed_sg_id
  description                  = "CloudFront VPC Origin managed SG"
}

resource "aws_security_group" "task" {
  name        = "${var.project}-backend-sg"
  description = "${var.project}-backend-sg"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-backend-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "task_from_alb" {
  security_group_id            = aws_security_group.task.id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = aws_security_group.alb.id
  description                  = "Allow HTTP from ALB"
}

resource "aws_lb_target_group" "backend" {
  name        = "${var.project}-backend-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    protocol            = "HTTP"
    path                = var.health_check_path
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

# internal: only reachable from inside the VPC (i.e. from the CloudFront
# VPC Origin ENIs). No public IP, no direct internet exposure.
resource "aws_lb" "internal" {
  name               = "${var.project}-internal-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.private_app[*].id
}

resource "aws_lb_listener" "internal_http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}
