########################################
## Data storage setup
########################################
resource "aws_ssm_parameter" "dockerfile" {
  name  = "/${var.tags.Billing}/${var.tags.Application}/Dockerfile"
  type  = "String"
  value = file("./files/Dockerfile")
}

resource "aws_ecr_repository" "app" {
  name = lower("${var.tags.Billing}/${var.tags.Application}")
}


########################################
## Codebuild Project
########################################
resource "aws_codebuild_project" "build" {
  name           = "${var.tags.Application}-build"
  description    = "Build docker image and publish to ECR"
  build_timeout  = "5"
  queued_timeout = "5"

  service_role = aws_iam_role.build.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  # This is of minimal use unless you're doing builds every 15 minutes, which is
  #   roughly the lifespan of build containers.
  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_SOURCE_CACHE"]
  }

  environment {
    # Note: using standard:4.0 as it's the newest image that still supports Node10
    #  Since I'm doing the build in the new container, this isn't strictly necessary,
    #  but it can save headaches in case it's changed to build in the build instance.
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:4.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    # Must run in privleged mode to build docker iamges
    privileged_mode = true

    # I find it easier to read as NAME = Value, and then use TF
    #   to convert it to the expected input for codebuild.
    dynamic "environment_variable" {
      for_each = {
        ECR_LOGIN_URL = split("/", aws_ecr_repository.app.repository_url)[0]
        ECR_REPO_NAME = aws_ecr_repository.app.name
        ECR_REPO_URL  = aws_ecr_repository.app.repository_url
        ECR_REGION    = split(":", aws_ecr_repository.app.arn)[3]
        IMAGE_TAG     = "latest"
      }
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }

    environment_variable {
      name  = "DOCKERFILE"
      type  = "PARAMETER_STORE"
      value = aws_ssm_parameter.dockerfile.name
    }
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/rearc/quest.git"
    buildspec       = file("./files/buildspec.yml")
    git_clone_depth = 1
  }
}

########################################
## Build Service Role
########################################
resource "aws_iam_role" "build" {
  name = "build"
  path = "/rearc/"
  assume_role_policy = jsonencode({
    Version = "2008-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = { Service = "codebuild.amazonaws.com" }
      Effect    = "Allow"
    }]
  })

  inline_policy {
    name   = "docker_builds"
    policy = data.aws_iam_policy_document.build.json
  }
}


data "aws_iam_policy_document" "build" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:GetAuthorizationToken",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    actions   = ["ssm:GetParameters"]
    resources = [aws_ssm_parameter.dockerfile.arn]
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
