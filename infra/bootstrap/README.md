# Bootstrap stack

Creates the S3 bucket that backs the workload's remote state
(`infra/environments/lab`). Applied once, by hand, by a single operator —
its own state stays **local** (never committed, never stored inside the
bucket it creates) because storing it there would be a chicken-and-egg
problem, and this stack is rarely re-run.

## Usage

```
cd infra/bootstrap
terraform init
terraform plan
terraform apply
```

## After applying

Record the output values below (also visible via `terraform output`) —
they're the `bucket` value the workload backend config
(`infra/environments/lab/backend.tf`) needs:

- `state_bucket_name`
- `aws_account_id`

## Why no DynamoDB lock table

Terraform 1.15.8 (pinned in `versions.tf`) supports S3-native state locking
(`use_lockfile = true` in the backend config), so a separate DynamoDB table
isn't needed. If the group ever downgrades below Terraform 1.10 / an
equivalent OpenTofu release, add an `aws_dynamodb_table` resource here
(`devops-g9-iac-tflock`, `PAY_PER_REQUEST`, partition key `LockID`) and
switch the workload backend to `dynamodb_table` instead.

## Safety notes

- This bucket must never be a target of `terraform destroy` run from
  `infra/environments/lab` — it lives in a separate state on purpose.
- Do not delete or empty this bucket while `infra/environments/lab` still
  has state stored in it.
