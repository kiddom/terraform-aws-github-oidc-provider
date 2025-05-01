/**
 * # AWS Github OIDC Provider Terraform Module
 *
 * ## Purpose
 * This module allows you to create a Github OIDC provider for your AWS account, that will help Github Actions to securely authenticate against the AWS API using an IAM role
 *
*/

locals {
  # ------------------------------------------------------------
  # Input validation for required inputs
  # ------------------------------------------------------------

  # Check that oidc_provider_arn is provided when create_oidc_provider is false
  validate_oidc_provider = var.create_oidc_provider || var.oidc_provider_arn != null

  # Check that oidc_role_arn is provided when create_oidc_role is false
  validate_oidc_role = var.create_oidc_role || var.oidc_role_arn != null

  # ------------------------------------------------------------
  # Inputs
  # ------------------------------------------------------------

  # Determine the provider ARN to use - either created by this module or externally provided
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.this[0].arn : var.oidc_provider_arn

  # Determine the role ARN to use - either created by this module or externally provided
  role_arn = var.create_oidc_role ? aws_iam_role.this[0].arn : var.oidc_role_arn

  # Extract role name from ARN for policy attachments when using existing role
  existing_role_name = (var.create_oidc_role || var.oidc_role_arn == null) ? null : element(split("/", var.oidc_role_arn), length(split("/", var.oidc_role_arn)) - 1)

  # For role name, use either the created role or the extracted name from ARN
  role_name = var.create_oidc_role ? aws_iam_role.this[0].name : local.existing_role_name

  # Determine whether to attach policies (when creating a role or explicitly requested for existing role)
  attach_policies = var.create_oidc_role || var.attach_policies_to_existing_role

  # Determine whether to update the assume role policy for an existing role
  update_role_policy = !var.create_oidc_role && var.update_existing_role_policy
}

resource "aws_iam_openid_connect_provider" "this" {
  count = var.create_oidc_provider ? 1 : 0
  client_id_list = [
    "sts.amazonaws.com",
  ]
  thumbprint_list = [var.github_thumbprint]
  url             = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "this" {
  count                = var.create_oidc_role ? 1 : 0
  name                 = var.role_name
  description          = var.role_description
  max_session_duration = var.max_session_duration
  assume_role_policy   = data.aws_iam_policy_document.this.json
  tags                 = var.tags
  path                 = var.iam_role_path
  permissions_boundary = var.iam_role_permissions_boundary
  depends_on           = [aws_iam_openid_connect_provider.this]
}

# Data source for existing role - used for validation and name resolution
data "aws_iam_role" "existing" {
  count = (!var.create_oidc_role && (var.update_existing_role_policy || var.attach_policies_to_existing_role)) ? 1 : 0
  name  = var.role_name

  # Add lifecycle to prevent terraform from failing if role doesn't exist during refresh
  lifecycle {
    postcondition {
      condition     = self.arn != null
      error_message = "The specified role ${var.role_name} does not exist"
    }
  }
}

# Update assume role policy for existing roles
resource "aws_iam_role" "existing_role_policy" {
  count              = local.update_role_policy ? 1 : 0
  name               = data.aws_iam_role.existing[0].name
  assume_role_policy = data.aws_iam_policy_document.this.json

  lifecycle {
    ignore_changes = [
      description,
      max_session_duration,
      permissions_boundary,
      tags,
      path,
      force_detach_policies,
      managed_policy_arns,
      inline_policy
    ]
  }
}

resource "aws_iam_role_policy_attachment" "attach" {
  count = local.attach_policies ? length(var.oidc_role_attach_policies) : 0

  policy_arn = var.oidc_role_attach_policies[count.index]
  # Use the validated role name from the data source when attaching to existing role
  role = var.create_oidc_role ? aws_iam_role.this[0].name : data.aws_iam_role.existing[0].name

  depends_on = [aws_iam_role.this, data.aws_iam_role.existing]
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
