# Two roles, split by purpose:
#   - execution role: what ECS itself needs to *start* the task
#     (pull image, write logs, resolve Secrets Manager values into env vars)
#   - task role: what the *application code* is allowed to do at runtime
#     (upload media objects to S3)
# Never merge these into one role — the execution role is effectively
# trusted by the ECS agent, not by application code.

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.project}-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Scoped to the exact secrets referenced by valueFrom in the task
# definitions below - not secretsmanager:* on "*".
data "aws_iam_policy_document" "task_execution_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.app.arn,
      aws_secretsmanager_secret.migration.arn,
    ]
  }
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  name   = "${var.project}-task-execution-secrets"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_secrets.json
}

resource "aws_iam_role" "task" {
  name               = "${var.project}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# Application can only PutObject under media/*. It cannot read, list, or
# delete - the app writes uploads, it never needs to serve them back
# through its own IAM identity (CloudFront/OAC handles reads).
data "aws_iam_policy_document" "task_media_upload" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.media.arn}/media/*"]
  }
}

resource "aws_iam_role_policy" "task_media_upload" {
  name   = "${var.project}-task-media-upload"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_media_upload.json
}
