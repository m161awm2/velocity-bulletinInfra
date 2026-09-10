# VPC: 10.20.0.0/16 across 2 AZs.
#   Public_A / Public_C      -> NAT Gateway only, no workloads.
#   Private_App_A / Private_App_C -> ECS tasks, internal ALB, CloudFront VPC Origin ENIs.
#
# Each private subnet routes 0.0.0.0/0 through the NAT Gateway *in the same AZ*.
# This is deliberate: a per-AZ NAT Gateway avoids cross-AZ data-processing
# charges and means a single NAT/AZ failure only affects that AZ's tasks,
# not the whole service (see README "단일 AZ 장애" goal).

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.main.id
  availability_zone       = var.azs[count.index]
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.project}-public-${substr(var.azs[count.index], -1, 1)}" }
}

resource "aws_subnet" "private_app" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  availability_zone = var.azs[count.index]
  cidr_block        = var.private_app_subnet_cidrs[count.index]

  tags = { Name = "${var.project}-private-app-${substr(var.azs[count.index], -1, 1)}" }
}

resource "aws_eip" "nat" {
  count  = length(var.azs)
  domain = "vpc"
  tags   = { Name = "${var.project}-nat-eip-${substr(var.azs[count.index], -1, 1)}" }
}

resource "aws_nat_gateway" "main" {
  count         = length(var.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.project}-nat-${substr(var.azs[count.index], -1, 1)}" }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private_app" {
  count  = length(var.azs)
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-private-app-rt-${substr(var.azs[count.index], -1, 1)}" }
}

resource "aws_route" "private_app_nat" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.private_app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id
}

resource "aws_route_table_association" "private_app" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

# S3 Gateway Endpoint: keeps ECR image-layer (backed by S3) and S3 API
# traffic off the NAT Gateway at no extra hourly cost.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private_app[*].id
  )

  tags = { Name = "${var.project}-s3-gw-endpoint" }
}
