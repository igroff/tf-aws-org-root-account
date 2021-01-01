provider "aws" {
  region = var.region
}

data "aws_iam_policy_document" "execution_policy" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    actions = [
      "ec2:DescribeInstances",
      "ec2:StopInstances"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "lambda_assume_role_policy_doc" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution_role" {
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy_doc.json
  description        = "Exeuction Role for ShutdownTaggedInstances Lambda"
}

resource "aws_iam_policy" "execution_policy" {
  description = "policy allowing creating and writing of cloudwatch log data"
  policy      = data.aws_iam_policy_document.execution_policy.json
}

resource "aws_iam_role_policy_attachment" "log_policy_attachment" {
  role       = aws_iam_role.execution_role.name
  policy_arn = aws_iam_policy.execution_policy.arn
}

data "archive_file" "lambda_hc_code_archive" {
  type        = "zip"
  source_dir  = "./handler_code"
  output_path = "./build/handler.zip"
}

resource "aws_lambda_function" "function" {
  function_name    = "ShutdownTaggedInstances-2"
  runtime          = "python3.8"
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.execution_role.arn
  timeout          = 10
  memory_size      = 128
  publish          = true
  filename         = data.archive_file.lambda_hc_code_archive.output_path
  source_code_hash = data.archive_file.lambda_hc_code_archive.output_base64sha256
  environment {
    variables = {
      SHUTDOWN_KEY   = "Shutdown"
      SHUTDOWN_VALUE = "nightly"
    }
  }
}

resource "aws_cloudwatch_event_rule" "nightly_schedule" {
  name                = "ShutdownTaggedInstancesNightly"
  schedule_expression = "cron(0 3 * * ? *)"
  description         = "Triggers the lambda that shuts down tagged instances (lambda function defines the tags)"
}

resource "aws_cloudwatch_event_target" "nightly_schedule" {
  rule = aws_cloudwatch_event_rule.nightly_schedule.name
  arn  = aws_lambda_function.function.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.nightly_schedule.arn
}