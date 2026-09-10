# Copy to terraform.tfvars (gitignored) and fill in real values.
# Never commit a file with real secrets in it.

database_url            = "postgresql://user:password@ep-xxxx-pooler.ap-southeast-1.aws.neon.tech/velocity?sslmode=require"
migration_database_url  = "postgresql://user:password@ep-xxxx.ap-southeast-1.aws.neon.tech/velocity?sslmode=require"

# backend_image is normally passed by CI as -var="backend_image=<ecr_repo_url>:<git-sha>"
# backend_image = "608420805531.dkr.ecr.ap-northeast-2.amazonaws.com/velocity-backend:latest"

# Leave unset on the first apply. Fill in after AWS creates the VPC Origin's
# managed security group post-association - see README "Terraform" section.
# cloudfront_vpc_origin_managed_sg_id = "sg-xxxxxxxxxxxxxxxxx"
