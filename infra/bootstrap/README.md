# Bootstrap stack

Applied once, by hand, by a single operator, per AWS account. Its own state
stays **local** (never committed, never stored inside the bucket it creates)
because storing it there would be a chicken-and-egg problem, and this stack
is rarely re-run.

It creates two things:

1. **The S3 bucket that backs the workload's remote state**
   (`infra/environments/lab`) — `devops-g9-iac-tfstate-<account-id>`,
   versioned, encrypted, public access blocked, TLS-only bucket policy.
2. **The GitHub Actions OIDC provider + CI deploy role**
   (`github-oidc.tf`) — lets `.github/workflows/container-ci-cd.yml` push
   images to the `devops-g9-iac-*` ECR repos with short-lived credentials,
   no IAM access keys stored in GitHub. The role has ECR push/pull only —
   no Terraform or state access.

## Usage

```
cd infra/bootstrap
terraform init
terraform plan
terraform apply
```

If the account **already has** a GitHub OIDC provider (only one per account
is allowed — e.g. it was created by the manual build), reuse it:

```
terraform apply \
  -var create_github_oidc=false \
  -var github_oidc_provider_arn=arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com
```

The `github_repo` variable defaults to `emebetgirmay/Service-Environment`;
override it with `-var github_repo=owner/repo` if the remote differs.

## After applying

Record the outputs (`terraform output`):

| Output | Used for |
|---|---|
| `state_bucket_name` | the `bucket` line in `infra/environments/lab/backend.hcl` |
| `aws_account_id` | sanity-check you're in the right account |
| `github_actions_role_arn` | GitHub → repo **Settings → Secrets and variables → Actions → Variables** → new variable `AWS_DEPLOY_ROLE_ARN` |

Then continue with `docs/iac/new-account-runbook.md`.

## Why no DynamoDB lock table

Terraform ≥ 1.10 supports S3-native state locking (`use_lockfile = true` in
the backend config), so a separate DynamoDB table isn't needed. If the
group ever downgrades below 1.10, add an `aws_dynamodb_table` here
(`devops-g9-iac-tflock`, `PAY_PER_REQUEST`, partition key `LockID`) and
switch the workload backend to `dynamodb_table`.

## Safety notes

- The state bucket must never be a target of `terraform destroy` run from
  `infra/environments/lab` — it lives in a separate state on purpose.
- Do not delete or empty the bucket while `infra/environments/lab` still
  has state stored in it.
