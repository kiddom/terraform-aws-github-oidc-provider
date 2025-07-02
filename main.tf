/**
 * # AWS Github OIDC Provider Terraform Module
 *
 * ## Purpose
 * This module allows you to create a Github OIDC provider for your AWS account, that will help Github Actions to securely authenticate against the AWS API using an IAM role
 *
*/

locals {
  # validations
  validate_oidc_provider = var.create_oidc_provider || var.oidc_provider_arn != null
  validate_oidc_role     = var.create_oidc_role || var.oidc_role_arn != null

  # toggles
  attach_policies    = var.create_oidc_role || var.attach_policies_to_existing_role
  update_role_policy = !var.create_oidc_role && var.update_existing_role_policy

  # pick the created ARN or fall back to external
  oidc_provider_arn = try(
    aws_iam_openid_connect_provider.this["oidc"].arn,
    var.oidc_provider_arn,
  )

  role_arn = try(
    aws_iam_role.this["role"].arn,
    var.oidc_role_arn,
  )

  # Extract role name from ARN for policy attachments when using existing role
  existing_role_name = (var.create_oidc_role || var.oidc_role_arn == null) ? null : element(split("/", var.oidc_role_arn), length(split("/", var.oidc_role_arn)) - 1)

  # For role name, use either the created role or the extracted name from ARN
  role_name = var.create_oidc_role ? aws_iam_role.this[0].name : local.existing_role_name
}

resource "aws_iam_openid_connect_provider" "this" {
  for_each = var.create_oidc_provider ? { oidc = true } : {}

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [var.github_thumbprint]
}

resource "aws_iam_role" "this" {
  for_each = var.create_oidc_role ? { role = true } : {}

  name                 = var.role_name
  description          = var.role_description
  max_session_duration = var.max_session_duration
  assume_role_policy   = data.aws_iam_policy_document.this.json
  tags                 = var.tags
  path                 = var.iam_role_path
  permissions_boundary = var.iam_role_permissions_boundary

  depends_on = [aws_iam_openid_connect_provider.this]
}

# Update assume role policy for existing roles
resource "aws_iam_role" "existing_role_policy" {
  for_each = local.update_role_policy ? { (var.role_name) = var.role_name } : {}

  name               = each.key
  assume_role_policy = data.aws_iam_policy_document.this.json

  lifecycle {
    ignore_changes = [
      description,
      max_session_duration,
      permissions_boundary,
      tags,
      path,
      force_detach_policies,
      inline_policy
    ]
  }
}

resource "aws_iam_role_policy_attachment" "attach" {
  for_each = local.attach_policies ? toset(var.oidc_role_attach_policies) : toset([])

  policy_arn = each.value
  role       = local.role_name

  depends_on = [aws_iam_role.this]
}

# Create the policy document for all cases (new roles and for updating existing roles)
data "aws_iam_policy_document" "this" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test = "StringLike"
      values = [
        for repo in var.repositories :
        "repo:%{if length(regexall(":+", repo)) > 0}${repo}%{else}${repo}:*%{endif}"
      ]
      variable = "token.actions.githubusercontent.com:sub"
    }

    principals {
      identifiers = [local.oidc_provider_arn]
      type        = "Federated"
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

check "github_oidc_provider_validation" {
  assert {
    condition = (
      var.max_session_duration >= 3600 &&
      var.max_session_duration <= 43200 &&
      (var.oidc_role_arn != null || var.create_oidc_role)
    )
    error_message = "Maximum session duration must be between 3600 and 43200 seconds."
  }

  assert {
    condition     = local.validate_oidc_provider
    error_message = "When create_oidc_provider is false, oidc_provider_arn must be provided"
  }

  assert {
    condition     = local.validate_oidc_role
    error_message = "When create_oidc_role is false, oidc_role_arn must be provided"
  }
}
