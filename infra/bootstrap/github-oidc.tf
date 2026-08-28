# --- GitHub Actions OIDC provider + CI deploy role ----------------------
# See variables.tf for the rationale. Everything here is gated on
# var.create_github_oidc so the stack still applies cleanly in an account
# that already has the GitHub OIDC provider (AWS allows only one provider
# per issuer URL per account).

locals {
  # Create the CI deploy role when we're either creating the OIDC provider
  # here, or reusing a pre-existing one (ARN supplied). When both are false
  # the whole file is a no-op — e.g. the account's permission set can't do
  # IAM writes and the instructor provisions the role/provider separately.
  create_github_ci_role = var.create_github_oidc || var.github_oidc_provider_arn != null

  github_oidc_arn = var.create_github_oidc ? (
    aws_iam_openid_connect_provider.github[0].arn
  ) : var.github_oidc_provider_arn

  # CI is allowed to assume the role from a push to main or from a
  # pull_request workflow run in this repo — nothing else.
  github_oidc_subjects = [
    "repo:${var.github_repo}:ref:refs/heads/main",
    "repo:${var.github_repo}:pull_request",
  ]
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS validates the GitHub OIDC cert against its own trust store now, so
  # these thumbprints are no longer security-critical, but the argument is
  # still required. GitHub's current + prior intermediate CA thumbprints:
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = { Name = "github-actions-oidc" }
}

data "aws_iam_policy_document" "github_actions_trust" {
  count = local.create_github_ci_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_oidc_subjects
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count = local.create_github_ci_role ? 1 : 0

  name                 = "devops-g9-iac-github-actions"
  description          = "Assumed by GitHub Actions via OIDC to push images to the devops-g9-iac-* ECR repos."
  assume_role_policy   = data.aws_iam_policy_document.github_actions_trust[0].json
  max_session_duration = 3600

  tags = { Name = "devops-g9-iac-github-actions" }
}

data "aws_iam_policy_document" "github_actions_ecr" {
  count = local.create_github_ci_role ? 1 : 0

  # ECR auth token is account-wide by API design.
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push/pull scoped to this project's repos only.
  statement {
    sid    = "EcrPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/devops-g9-iac-*",
    ]
  }
}

resource "aws_iam_role_policy" "github_actions_ecr" {
  count = local.create_github_ci_role ? 1 : 0

  name   = "ecr-push"
  role   = aws_iam_role.github_actions[0].id
  policy = data.aws_iam_policy_document.github_actions_ecr[0].json
}
