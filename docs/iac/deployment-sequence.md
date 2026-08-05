# Deployment Sequence & Dependency Types

Written in response to Gate 1 review feedback ("Small Improvements During
Implementation" #1 and #2): distinguish dependency types instead of
treating everything as one flat sequential chain, and write down the
actual first-deployment order instead of leaving it implicit.

---

## Three kinds of dependency

Not every arrow in the Gate 1 dependency graph means the same thing.
Collapsing them into one diagram is what made the original graph read as
"everything must happen in order," which isn't true.

| Type | What it means | Who enforces it | Examples from this build |
|---|---|---|---|
| **Creation** | Resource A must exist before Terraform can create resource B, because B's config literally references an attribute of A | Terraform's own dependency graph — automatic, you can't get this wrong | VPC before subnets; subnets + security group before the ECS service; IAM role before the task definition (task def needs the role's ARN) |
| **Runtime** | Both sides must be *working* at the same moment for the app to function, but Terraform's graph has no idea whether that's true | Nothing automatic — this is what Gate 2's runtime proof and the architecture tests exist to catch | A real image must exist at the tag a task definition references (Terraform will happily create a task def pointing at a tag nobody ever pushed); the security-group rules must match what the app code actually calls (see Predicted Edge #1 — Terraform applies cleanly either way); Service Connect DNS must be registered by the time a dependent task's proxy starts (the manual build's B-started-before-C gotcha) |
| **Operational** | Not required for the app to work at all — required for a human to observe/debug/operate it | Whoever's on call | CloudWatch log group (app runs fine with nobody watching); ECS Exec + the SSM VPC endpoints (only matters the moment someone tries to shell in); Container Insights (deliberately not enabled here) |

The practical use of this split: a clean `terraform apply` only proves the
**creation** dependencies were satisfied. It proves nothing about runtime
or operational dependencies — those need the runtime proof step (Gate 2
style: curl the ALB, `ecs execute-command` in, check CloudWatch) regardless
of how green the apply looked.

---

## First-time deployment sequence (from an empty environment)

ECS services cannot reach a healthy state until a real image exists at the
tag they reference — but the ECR repo that image gets pushed to is itself
created by Terraform (`ecs-service` module). That's a genuine chicken-and-
egg problem, not a modeling mistake, so the very first deployment needs
two `apply` passes. Every deployment after this one does not.

```
1. Bootstrap the state backend (once, ever, per environment)
   cd infra/bootstrap
   terraform init && terraform apply

2. Foundation infrastructure + ECR repos only (-target, first time only)
   cd infra/environments/lab
   cp terraform.tfvars.example terraform.tfvars
   # image tags aren't used by anything targeted below — but the variable's
   # own validation still requires a SHA-shaped placeholder, e.g. "0000000"
   terraform init
   terraform apply \
     -target=module.network \
     -target=module.alb \
     -target=module.ecs_platform \
     -target=module.service_a.aws_ecr_repository.this \
     -target=module.service_b.aws_ecr_repository.this \
     -target=module.service_c.aws_ecr_repository.this

3. Build and push real Git-SHA-tagged images
   terraform output ecr_repository_urls
   docker build -t <service_a_repo_url>:<real-sha> -f service-a/Dockerfile .
   docker push <service_a_repo_url>:<real-sha>
   # repeat for service-b, service-c

4. Full apply — everything else (ECS services, traffic-contract SG rules)
   # edit terraform.tfvars: replace the placeholder tags with the real SHAs
   terraform apply
```

After step 4, every future change — a new app version, a desired-count
bump, a tag change — is a normal `terraform apply` with no `-target`. The
repos already exist; only their *contents* (images) change going forward.

## Why `-target` here, and why that's not a routine habit

Terraform's own docs warn against `-target` as a regular workflow tool —
it's easy to leave the rest of the config in a state your last plan didn't
fully account for. This is the one legitimate exception the docs
themselves call out: a genuine bootstrapping ordering problem that only
exists once, on an empty environment. Every subsequent apply in this
project uses a full, untargeted plan.

## Egress trade-off — what changes in production

(See also `docs/iac/gate1-design.md` §3.) VPC endpoints instead of a NAT
Gateway is a lab-appropriate choice specifically because the current app
never calls anything outside the VPC. In a production deployment that
adds a real external dependency — a third-party API, a SaaS webhook, an
outbound email provider — the calculus changes: a NAT Gateway scales to
*any* destination for a flat cost, while VPC endpoints only cover
specific AWS services and need a new endpoint added (and its security
group updated) every time a new AWS service is called. Past roughly 3-4
external dependencies, or the first non-AWS dependency, a NAT Gateway
usually becomes the simpler operational choice even though it costs more
per month — this build stays endpoint-only because, today, that trade
hasn't been hit.
