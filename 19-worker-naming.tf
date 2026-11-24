
# Automatically name EKS worker EC2 instances.
# This does not modify or replace the EKS node group.

locals {
  eks_worker_asg_name       = aws_eks_node_group.node_group.resources[0].autoscaling_groups[0].name
  worker_naming_lambda_name = "${var.cluster_name}-worker-naming"
}

data "aws_caller_identity" "worker_naming" {}

# Package the Python Lambda function.
data "archive_file" "worker_naming" {
  type        = "zip"
  source_file = "${path.module}/worker_name_lambda.py"
  output_path = "${path.module}/.terraform/worker_name_lambda.zip"
}

# Lambda execution role.
resource "aws_iam_role" "worker_naming_lambda" {
  name = "${var.cluster_name}-worker-naming-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Permissions to inspect the worker ASG, tag its EC2 instances,
# and write Lambda logs.
resource "aws_iam_role_policy" "worker_naming_lambda" {
  name = "${var.cluster_name}-worker-naming-policy"
  role = aws_iam_role.worker_naming_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.worker_naming.account_id}:instance/*"
        Condition = {
          "ForAllValues:StringEquals" = {
            "aws:TagKeys" = ["Name"]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.worker_naming.arn}:*"
      }
    ]
  })
}

# Lambda log group with 14-day retention.
resource "aws_cloudwatch_log_group" "worker_naming" {
  name              = "/aws/lambda/${local.worker_naming_lambda_name}"
  retention_in_days = 14
}

# Lambda function.
resource "aws_lambda_function" "worker_naming" {
  function_name = local.worker_naming_lambda_name
  description   = "Automatically name EKS worker EC2 instances"

  role    = aws_iam_role.worker_naming_lambda.arn
  runtime = "python3.13"
  handler = "worker_name_lambda.lambda_handler"

  filename         = data.archive_file.worker_naming.output_path
  source_code_hash = data.archive_file.worker_naming.output_base64sha256

  timeout     = 60
  memory_size = 128

  environment {
    variables = {
      ASG_NAME = local.eks_worker_asg_name
    }
  }

  depends_on = [
    aws_iam_role_policy.worker_naming_lambda,
    aws_cloudwatch_log_group.worker_naming
  ]
}

# EventBridge rule: detect successful EKS worker launches.
resource "aws_cloudwatch_event_rule" "worker_launch" {
  name        = "${var.cluster_name}-worker-launch"
  description = "Detect successful launches in the EKS worker ASG"

  event_pattern = jsonencode({
    source        = ["aws.autoscaling"]
    "detail-type" = ["EC2 Instance Launch Successful"]
    detail = {
      AutoScalingGroupName = [local.eks_worker_asg_name]
    }
  })
}

resource "aws_cloudwatch_event_target" "worker_launch" {
  rule      = aws_cloudwatch_event_rule.worker_launch.name
  target_id = "WorkerNamingLambda"
  arn       = aws_lambda_function.worker_naming.arn
}

resource "aws_lambda_permission" "allow_worker_launch" {
  statement_id  = "AllowEventBridgeWorkerLaunch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.worker_naming.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.worker_launch.arn
}

# Scheduled reconciliation: check every five minutes for workers
# that may have been missed by an Auto Scaling event.
resource "aws_cloudwatch_event_rule" "worker_reconciliation" {
  name                = "${var.cluster_name}-worker-reconciliation"
  description         = "Periodically reconcile EKS worker Name tags"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "worker_reconciliation" {
  rule      = aws_cloudwatch_event_rule.worker_reconciliation.name
  target_id = "WorkerNamingReconciliationLambda"
  arn       = aws_lambda_function.worker_naming.arn
}

resource "aws_lambda_permission" "allow_worker_reconciliation" {
  statement_id  = "AllowEventBridgeWorkerReconciliation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.worker_naming.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.worker_reconciliation.arn
}
