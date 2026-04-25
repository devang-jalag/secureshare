# ECR Repository
resource "aws_ecr_repository" "janitor_repo" {
  name                 = "${var.project_name}-janitor-${var.environment}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  # Builds and pushes the Janitor Docker image on first provision,
  # this is for single-command IaC deployment.
  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<EOT
      $loginPwd = aws ecr get-login-password --region ${var.aws_region}
      $loginPwd | docker login --username AWS --password-stdin ${self.repository_url}
      docker build -t ${self.repository_url}:latest ${path.module}/../backend/
      docker push ${self.repository_url}:latest
    EOT
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "secure_share_cluster" {
  name = "${var.project_name}-cluster-${var.environment}"
}

# IAM — ECS Execution Role
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_name}-ecs-exec-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_managed_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM — ECS Task Role
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecs-task-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }]
  })
}

resource "aws_iam_policy" "janitor_policy" {
  name        = "${var.project_name}-janitor-policy-${var.environment}"
  description = "Allows the Janitor task to delete expired S3 objects and DynamoDB records"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:DeleteObject"]
        Resource = [
          aws_s3_bucket.secure_share_bucket.arn,
          "${aws_s3_bucket.secure_share_bucket.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:Scan", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.secure_share_metadata.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_policy_attach" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.janitor_policy.arn
}

# Fargate Task Definition
resource "aws_ecs_task_definition" "janitor_task" {
  family                   = "${var.project_name}-janitor"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "janitor"
      image     = "${aws_ecr_repository.janitor_repo.repository_url}:latest"
      essential = true

      environment = [
        { name = "S3_BUCKET_NAME", value = aws_s3_bucket.secure_share_bucket.id },
        { name = "DYNAMODB_TABLE_NAME", value = aws_dynamodb_table.secure_share_metadata.name }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}-janitor"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_cloudwatch_log_group" "janitor_logs" {
  name              = "/ecs/${var.project_name}-janitor"
  retention_in_days = 7
}

# EventBridge Scheduled Rule
resource "aws_cloudwatch_event_rule" "hourly_janitor" {
  name                = "${var.project_name}-hourly-janitor"
  description         = "Triggers the Janitor Fargate task every hour"
  schedule_expression = "rate(1 hour)"
}

# Networking (custom VPC required — no default VPC exists in this environment)
resource "aws_vpc" "janitor_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.project_name}-janitor-vpc" }
}

resource "aws_internet_gateway" "janitor_igw" {
  vpc_id = aws_vpc.janitor_vpc.id
}

resource "aws_subnet" "janitor_subnet" {
  vpc_id                  = aws_vpc.janitor_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_route_table" "janitor_rt" {
  vpc_id = aws_vpc.janitor_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.janitor_igw.id
  }
}

resource "aws_route_table_association" "janitor_rta" {
  subnet_id      = aws_subnet.janitor_subnet.id
  route_table_id = aws_route_table.janitor_rt.id
}

# EventBridge → ECS target
resource "aws_cloudwatch_event_target" "run_janitor_task" {
  target_id = "run-janitor-task"
  rule      = aws_cloudwatch_event_rule.hourly_janitor.name
  arn       = aws_ecs_cluster.secure_share_cluster.arn
  role_arn  = aws_iam_role.eventbridge_ecs_role.arn

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.janitor_task.arn
    task_count          = 1
    launch_type         = "FARGATE"

    network_configuration {
      subnets          = [aws_subnet.janitor_subnet.id]
      assign_public_ip = true
    }
  }
}

# IAM — EventBridge Role
resource "aws_iam_role" "eventbridge_ecs_role" {
  name = "${var.project_name}-eventbridge-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "events.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_ecs_policy" {
  role       = aws_iam_role.eventbridge_ecs_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceEventsRole"
}

# Outputs
output "ecr_repository_url" {
  value       = aws_ecr_repository.janitor_repo.repository_url
  description = "ECR repository URL for the Janitor image"
}
