# Preserve Terraform addresses when upgrading from the internal-ALB layout.
# The ALB still needs replacement because its scheme and name change.
moved {
  from = aws_lb.internal
  to   = aws_lb.public
}

moved {
  from = aws_lb_listener.internal_http
  to   = aws_lb_listener.public_http
}
