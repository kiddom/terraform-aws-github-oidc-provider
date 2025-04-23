terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "github_oidc" {
  source = "../.."

  create_oidc_provider = true
  create_oidc_role     = true

  repositories              = ["terraform-module/terraform-aws-github-oidc-provider:ref:refs/heads/main"]
  oidc_role_attach_policies = ["arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"]
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN"
  value       = module.github_oidc.oidc_provider_arn
}

output "github_oidc_role" {
  description = "CICD GitHub role ARN"
  value       = module.github_oidc.oidc_role_arn
}
