provider "aws" {
  region = "ap-southeast-1"
}

terraform {
  # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest
  required_providers {
    aws = {
      version = "~> 3.74.3"
    }
  }
}
