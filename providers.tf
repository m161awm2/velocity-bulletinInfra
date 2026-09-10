# CloudFront resources (distribution, VPC Origin, OAC, WAF) are global and
# must be created via the us-east-1 endpoint regardless of workload region.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = "velocity-bulletin"
      Managed = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project = "velocity-bulletin"
      Managed = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
