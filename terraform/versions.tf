terraform {
  required_version = ">= 1.7, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region  = "sa-east-1"
  profile = var.aws_profile
  default_tags {
    tags = { Project = "brazil-tailscale-exit", ManagedBy = "Terraform" }
  }
}
