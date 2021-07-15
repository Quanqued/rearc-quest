variable "region" {
  description = "The region to deploy resources in"
  type        = string
  default     = "us-west-2"
}

terraform {
  required_version = ">= 0.15"

  required_providers {
    aws = ">= 3"
  }
}


provider "aws" {
  region = var.region
  default_tags {
    tags = var.tags
  }
}
