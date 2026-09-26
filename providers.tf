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
