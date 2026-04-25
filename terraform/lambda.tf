# IAM Role
resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.project_name}-lambda-policy-${var.environment}"
  description = "Least-privilege policy for Lambda functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "${aws_s3_bucket.secure_share_bucket.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:Scan", "dynamodb:GetItem"]
        Resource = aws_dynamodb_table.secure_share_metadata.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda Deployment Package
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/src"
  output_path = "${path.module}/../backend/build/lambda_function.zip"
}

# Lambda Functions
resource "aws_lambda_function" "presigned_url_generator" {
  function_name    = "${var.project_name}-generate-url-${var.environment}"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      S3_BUCKET_NAME      = aws_s3_bucket.secure_share_bucket.id
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.secure_share_metadata.name
      FORCE_DEPLOY        = "2"
    }
  }
}

resource "aws_lambda_function" "list_files" {
  function_name    = "${var.project_name}-list-files-${var.environment}"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "list_files.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.secure_share_metadata.name
      FORCE_DEPLOY        = "2"
    }
  }
}

resource "aws_lambda_function" "download_url" {
  function_name    = "${var.project_name}-download-url-${var.environment}"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "download.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      S3_BUCKET_NAME      = aws_s3_bucket.secure_share_bucket.id
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.secure_share_metadata.name
      FORCE_DEPLOY        = "2"
    }
  }
}

# Outputs
output "lambda_function_name" {
  value       = aws_lambda_function.presigned_url_generator.function_name
  description = "Name of the presigned URL generator Lambda"
}
