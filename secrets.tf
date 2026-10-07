# JWT_SECRET is the one value Terraform is allowed to generate itself
# (equivalent to `openssl rand -hex 32`). DATABASE_URL comes from Neon
# and must be supplied as a variable -
# see variables.tf for how to pass them in without committing them.
resource "random_id" "jwt_secret" {
  byte_length = 32
}

# Shared database and app secret. ECS resolves each JSON key individually via
# `valueFrom = "<secret-arn>:<key>::"` in the task definition, so the
# container only ever sees DATABASE_URL and JWT_SECRET as plain env vars.
resource "aws_secretsmanager_secret" "app" {
  name = "${var.project}SecretManager"
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    DATABASE_URL = var.database_url
    JWT_SECRET   = random_id.jwt_secret.hex
  })
}
