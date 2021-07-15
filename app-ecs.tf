########################################
## Input Variables
########################################
variable "app_port" {
  description = "The port used by the application"
  type        = number
  default     = 3000
}

variable "app_secret" {
  description = "The secret word to pass to the container (set using TFVAR_ or other secure method)"
  type        = string
  default     = "not a secret"
}


########################################
## ECS Service
########################################
resource "aws_ecs_cluster" "main" {
  name               = var.tags.Billing
  capacity_providers = ["FARGATE"]
}

resource "aws_security_group" "app_ecs" {
  name_prefix = "app-"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol        = "tcp"
    from_port       = var.app_port
    to_port         = var.app_port
    security_groups = [aws_security_group.app_lb.id]
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Store the secret encrypted
resource "aws_ssm_parameter" "app_secret" {
  name  = "/${var.tags.Billing}/${var.tags.Application}/SecretWord"
  type  = "SecureString"
  value = var.app_secret
}

resource "aws_ecs_task_definition" "app" {
  family             = var.tags.Application
  execution_role_arn = aws_iam_role.task.arn

  cpu                      = 256
  memory                   = 512
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  container_definitions = jsonencode([{
    name   = var.tags.Application
    image  = aws_ecr_repository.app.repository_url
    cpu    = 256
    memory = 512
    portMappings = [{
      containerPort = var.app_port
      hostPort      = var.app_port
    }]
    secrets = [{
      name      = "SECRET_WORD"
      valueFrom = aws_ssm_parameter.app_secret.arn
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/${var.tags.Application}"
        awslogs-region        = var.region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name            = var.tags.Application
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn

  # Using the default role
  #iam_role    = "arn:aws:iam::aws:policy/aws-service-role/AmazonECSServiceRolePolicy"
  launch_type = "FARGATE"

  desired_count = 1
  lifecycle {
    ignore_changes = [desired_count]
  }

  network_configuration {
    subnets         = [for s in aws_subnet.private : s.id]
    security_groups = [aws_security_group.app_ecs.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.tags.Application
    container_port   = var.app_port
  }

  propagate_tags = "SERVICE"
}



########################################
## Task Execution Role
########################################
resource "aws_iam_role" "task" {
  name = "task"
  path = "/rearc/"
  assume_role_policy = jsonencode({
    Version = "2008-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Effect    = "Allow"
    }]
  })

  inline_policy {
    name   = "ecs_task"
    policy = data.aws_iam_policy_document.task.json
  }
}


data "aws_iam_policy_document" "task" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetAuthorizationToken",
      "ecr:GetDownloadUrlForLayer"
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    actions = [
      "ssm:GetParameters",
      "kms:Decrypt"
    ]
    resources = [
      aws_ssm_parameter.app_secret.arn,
      data.aws_kms_alias.ssm.arn
    ]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

# Get ARN for default ssm encryption key
data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}
