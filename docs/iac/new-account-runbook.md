# New-Account Deployment Runbook

**Task:** redeploy the whole stack from scratch in the new AWS account,
keep Region `eu-north-1`, prove Services A/B/C come up, and repoint GitHub
Actions at the new account.

This runbook is the greenfield path. It reuses the two-pass bootstrap order
already documented in [`deployment-sequence.md`](./deployment-sequence.md)
and adds the account-switch specifics.

**New account:** `240462142849` ("AkiraChix" / DevOpsCohort), Region
`eu-north-1`, SSO permission set `DevOpsCohort-group9-eu-north-1`. See
[Deviations found during the first real deployment](#deviations-found-during-the-first-real-deployment)
at the bottom — this shared account behaves differently from a standalone
one in three ways that the code now handles behind feature flags.

| Assignment requirement | Covered by |
|---|---|
| Deploy all services from scratch in the new account | Steps 1, 4, 5 |
| Reset the Terraform state locks as needed | Step 6 |
| Retain the group's assigned Region | Enforced in code — `aws_region` validation pins `eu-north-1` in every stack; nothing to do |
| Confirm Services A, B, C deploy successfully | Step 5 |
| Update GitHub Actions to auth + deploy to the new account | Steps 2, 7 |

---

## What changed in the repo to make this possible

- `infra/environments/lab/backend.tf` is now a **partial** backend — the
  state-bucket name (which embeds the account ID) is supplied at
  `init` time from `backend.hcl`, not hard-coded. Old value was
  `devops-g9-iac-tfstate-827478161993`.
- `infra/bootstrap/` now also creates a **GitHub OIDC provider + CI deploy
  role** (`github-oidc.tf`), output as `github_actions_role_arn`.
- `.github/workflows/container-ci-cd.yml` has a new `push-images` job that
  assumes that role via OIDC and pushes `<git-sha>` images to ECR on merge
  to `main`. No AWS keys are stored in GitHub.
- `required_version` relaxed from `= 1.15.8` to `>= 1.15.8, < 1.16.0`.

---

## Prerequisites

- Terraform `>= 1.15.8, < 1.16.0` — `terraform version`
- AWS CLI v2 — `aws --version`
- Docker (for building/pushing the first images) — `docker version`
- The new account's credentials from the DM. Configure them as a named
  profile so nothing leaks into the wrong account:

  ```bash
  aws configure --profile g9-new
  # or, for temporary creds, export AWS_ACCESS_KEY_ID / _SECRET_ACCESS_KEY / _SESSION_TOKEN
  export AWS_PROFILE=g9-new
  export AWS_REGION=eu-north-1
  ```

---

## Step 0 — Confirm you are in the new account and the right Region

```bash
aws sts get-caller-identity          # note the Account field — must be the NEW id
aws configure get region             # must print eu-north-1
```

Stop here if the account ID is still `827478161993` (the old one) or the
Region is anything other than `eu-north-1`.

---

## Step 1 — Bootstrap the state backend + CI role (once per account)

```bash
cd infra/bootstrap
terraform init
terraform apply
```

If `terraform apply` fails on `EntityAlreadyExists` for the GitHub OIDC
provider (the account already has one — e.g. from the manual build), re-run
with it disabled and point at the existing provider:

```bash
terraform apply \
  -var create_github_oidc=false \
  -var github_oidc_provider_arn=arn:aws:iam::<NEW_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com
```

Record the outputs:

```bash
terraform output
# state_bucket_name       = "devops-g9-iac-tfstate-<NEW_ACCOUNT_ID>"
# aws_account_id          = "<NEW_ACCOUNT_ID>"
# github_actions_role_arn = "arn:aws:iam::<NEW_ACCOUNT_ID>:role/devops-g9-iac-github-actions"
```

> Bootstrap state is local by design. Keep `infra/bootstrap/terraform.tfstate`
> on the operator's machine — do not commit it, do not move it into the
> bucket it just created.

---

## Step 2 — Point GitHub Actions at the new account

GitHub → repo **Settings → Secrets and variables → Actions → Variables** →
**New repository variable**:

| Name | Value |
|---|---|
| `AWS_DEPLOY_ROLE_ARN` | the `github_actions_role_arn` output from Step 1 |

That is the only GitHub-side change. The workflow already references
`${{ vars.AWS_DEPLOY_ROLE_ARN }}` and `eu-north-1`. If an old
`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` secret exists from a previous
attempt, delete it — it is unused and points at the old account.

---

## Step 3 — Initialise the workload backend against the new bucket

```bash
cd ../environments/lab
cp backend.hcl.example backend.hcl
# edit backend.hcl: bucket = "devops-g9-iac-tfstate-<NEW_ACCOUNT_ID>"

terraform init -reconfigure -backend-config=backend.hcl
```

`-reconfigure` tells Terraform to use the new backend without trying to
migrate state from the old one (there is nothing to migrate — this is a
fresh account).

Create `terraform.tfvars` from the example:

```bash
cp terraform.tfvars.example terraform.tfvars
# set owner_tags to the real names; leave the image tags as a 7-hex
# placeholder for now, e.g. 0000000 — the first apply below doesn't use them
```

---

## Step 4 — Two-pass first apply (chicken-and-egg: ECR repo before image)

**Pass 1 — foundation + empty ECR repos only:**

```bash
terraform apply \
  -target=module.network \
  -target=module.alb \
  -target=module.ecs_platform \
  -target=module.service_a.aws_ecr_repository.this \
  -target=module.service_b.aws_ecr_repository.this \
  -target=module.service_c.aws_ecr_repository.this
```

**Build and push the first real images** (Git SHA tags, `latest` is rejected):

```bash
SHA=$(git rev-parse HEAD)
ACCOUNT=<NEW_ACCOUNT_ID>
REG=$ACCOUNT.dkr.ecr.eu-north-1.amazonaws.com
aws ecr get-login-password --region eu-north-1 | docker login --username AWS --password-stdin $REG

for s in a b c; do
  docker build -t $REG/devops-g9-iac-service-$s:$SHA -f service-$s/Dockerfile .
  docker push $REG/devops-g9-iac-service-$s:$SHA
done
```

**Pass 2 — full apply with the real tags:**

```bash
# edit terraform.tfvars: service_a_image_tag / _b_ / _c_ = "<that SHA>"
terraform apply
```

Every apply after this one is a plain `terraform apply` — no `-target`.

---

## Step 5 — Confirm Services A, B, C deploy successfully

```bash
terraform output alb_dns_name
CLUSTER=$(terraform output -raw cluster_name)

# ECS: all three services should reach runningCount == desiredCount
aws ecs describe-services --cluster "$CLUSTER" \
  --services devops-g9-iac-svc-a devops-g9-iac-svc-b devops-g9-iac-svc-c \
  --query 'services[].{name:serviceName,desired:desiredCount,running:runningCount,deployments:length(deployments)}' \
  --output table

# ALB target group for Service A should be "healthy"
aws elbv2 describe-target-health \
  --target-group-arn "$(aws elbv2 describe-target-groups \
     --names devops-g9-iac-tg-service-a --query 'TargetGroups[0].TargetGroupArn' --output text)" \
  --query 'TargetHealthDescriptions[].TargetHealth.State' --output text

# End-to-end through the ALB
ALB=$(terraform output -raw alb_dns_name)
curl -fsS "http://$ALB/health"
curl -fsS -X POST "http://$ALB/request"      # exercises A -> B -> C
```

Expected: three services `running == desired` (A=2, B=1, C=1), target group
`healthy`, `/health` returns 200.

> **Known, documented gap:** the C→A `/callback` has no security-group rule
> (Gate 1 Predicted Edge #1 / Scar 1). The forward chain A→B→C responds
> fine; the callback fails closed until Robert approves SG-7 or the app
> drops the synchronous callback. This is expected, not a deployment
> failure. Evidence to cite: a `REJECT` in VPC Flow Logs for
> `sg-svc-c → sg-svc-a:3001` and a `failed_to_callback_a` entry in Service
> C's log group `/ecs/devops-g9-iac/service-c`.

Per-service logs if anything is unhealthy:

```bash
aws logs tail /ecs/devops-g9-iac/service-a --since 10m --follow
```

---

## Step 6 — Reset Terraform state locks as needed

The workload backend uses **S3-native locking** (`use_lockfile = true`) — a
lock is a small object at `s3://devops-g9-iac-tfstate-<acct>/lab/workload.tfstate.tflock`.
A lock only lingers if a previous `plan`/`apply` was killed (Ctrl-C, CI
runner timeout, dropped network) mid-run.

**Preferred — let Terraform release it:**

```bash
cd infra/environments/lab
terraform force-unlock <LOCK_ID>     # the ID is printed in the "Error acquiring the state lock" message
```

**If `force-unlock` can't find the lock / backend is half-initialised —
delete the lock object directly:**

```bash
aws s3 rm s3://devops-g9-iac-tfstate-<NEW_ACCOUNT_ID>/lab/workload.tfstate.tflock
```

**Notes:**

- Only do this when you are certain no other `apply` is actually running.
- The `infra/bootstrap` stack has **no** remote lock (its state is local),
  so there is nothing to unlock there.
- A brand-new account/bucket starts with zero locks — this step is only
  needed if an earlier run in this account was interrupted.

---

## Step 7 — Verify the GitHub Actions pipeline against the new account

1. Merge these repo changes to `main` (or use **Actions → Container CI/CD →
   Run workflow** on the branch).
2. Watch the **`push-images`** jobs. Each assumes
   `AWS_DEPLOY_ROLE_ARN` via OIDC, logs in to ECR in the new account, and
   pushes `devops-g9-iac-service-{a,b,c}:<git-sha>`.
3. Confirm the images landed:

   ```bash
   aws ecr describe-images --repository-name devops-g9-iac-service-a \
     --query 'imageDetails[].imageTags' --output text
   ```

4. To actually roll a new image to ECS, the Release owner bumps
   `service_*_image_tag` in `terraform.tfvars` to that SHA and runs
   `terraform apply` — CI does **not** deploy (Gate 1 design §8: CI builds,
   IaC deploys).

---

## Teardown (between cycles)

```bash
cd infra/environments/lab
terraform destroy                    # workload only — never touches the state bucket

# bootstrap stays up; only tear it down if you're abandoning the account:
cd ../bootstrap
terraform destroy
```

`terraform destroy` on the workload cannot reach the state bucket or the CI
role — they live in the separate `infra/bootstrap` state.

---

## Deviations found during the first real deployment

The `240462142849` account is shared across cohort groups g1-g10 and is
more locked-down than the standalone account the Gate 1 design assumed.
Four things surfaced on the first end-to-end apply. All are handled in code
now; this section is the record of why.

### 1. Security-group descriptions must be plain ASCII

`CreateSecurityGroup` / `AuthorizeSecurityGroupIngress` reject non-ASCII.
The module descriptions used `—` (em-dash) and `->` (the `>` char isn't in
the allowed set for *rule* descriptions). Fixed in `modules/alb`,
`modules/network`, `modules/ecs-service`, and `sg-traffic-contract.tf` —
em-dash → `-`, `->` → `to`. Not account-specific; would have failed
anywhere.

### 2. Cohort permission set can't create an IAM OIDC provider

`iam:CreateOpenIDConnectProvider` is denied for
`DevOpsCohort-group9-eu-north-1`, but the account already has the GitHub
OIDC provider (other groups use it). `infra/bootstrap` now takes
`create_github_oidc = false` + `github_oidc_provider_arn = ...` and creates
only the `devops-g9-iac-github-actions` role against the existing provider.
Committed in `infra/bootstrap/terraform.tfvars.example`. Role creation for
`devops-g9-*` names **is** allowed, so the workload's task roles applied
fine.

### 3. Interface-endpoint private DNS is not honoured → NAT Gateway required

With `enable_nat_gateway = false` (the Gate 1 NAT-free posture), every ECS
task failed `CannotPullContainerError` — `dial tcp <public-ecr-ip>:443:
i/o timeout`. Investigated and ruled out: VPC DNS attributes (both on),
DHCP options (`AmazonProvidedDNS`), endpoint state (`available`,
`PrivateDnsEnabled: true`), the AWS-managed `dkr.ecr.eu-north-1.amazonaws.com`
private zone (associated with the VPC), endpoint SG, route tables, and
resolver rules (only the default `internet-resolver`). Despite all of that
correct, the VPC resolver returns **public** ECR IPs to tasks. This VPC
does not apply interface-endpoint private DNS — likely an account/Org-level
constraint the group can't change.

Fix: `enable_nat_gateway = true` in `infra/environments/lab/terraform.tfvars`.
Adds one NAT Gateway + EIP + a `0.0.0.0/0` route on the private route
table, **and** — because the service SGs restrict egress to the endpoint SG
only — a `0.0.0.0/0:443` egress rule per service SG (`allow_public_egress`,
wired from `enable_nat_gateway`). The interface endpoints are left in place
(harmless; they'd be used if private DNS ever started working).

This is a deliberate, documented departure from the "no-NAT, cost-aware"
Gate 1 decision, forced by the environment. In the group's own standalone
account the flag stays `false`.

### 4. Edge #1 (C -> A callback) reproduced exactly as predicted

After the services were healthy, `POST /request` with a JSON body returns
**504** — Service A reaches B, B reaches C, C tries to call back to
`service-a:3001/callback`, no SG rule permits C -> A (SG-7 is deliberately
not implemented), the callback hangs, the synchronous chain times out at
the ALB. This is the Gate 1 "Predicted Edge #1 / Scar 1" happening live.
`GET /health` through the ALB returns 200; the A->B->C forward path
processes. Left as-is pending the SG-7 decision with the instructor.

### Also: Terraform version pin

`required_version` was `= 1.15.8`; local/CI Terraform is 1.15.9. Relaxed to
`>= 1.15.8, < 1.16.0` in both stacks so `init` doesn't fail on the exact
pin.
