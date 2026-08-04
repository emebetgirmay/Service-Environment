# Gate 1 — Five Architecture Decision Cards

Companion to [`gate1-design.md`](./gate1-design.md). Group 9, eu-north-1.

Each card answers: what risk are we reducing, what trade-off are we accepting, which AWS
Well-Architected pillar is most relevant, and what evidence will prove the design works.

---

## 1. Two Availability Zones

- **Risk reduced:** a single-AZ outage (power, networking, or capacity event) taking
  down the ALB or all of Service A's tasks at once.
- **Trade-off accepted:** double the subnets and route-table entries to design and
  reason about, plus cross-AZ data-transfer cost whenever a Service Connect call happens
  to land on a task in the other AZ.
- **Pillar:** Reliability.
- **Evidence:** `aws ecs describe-tasks` shows Service A's two tasks reporting different
  `availabilityZone` values; ALB target-group health checks pass in both AZs; manually
  stop the tasks in one AZ and show the ALB still serves successfully through the other.

## 2. Private Fargate tasks (no public IP)

- **Risk reduced:** direct internet exposure of application containers that would bypass
  the ALB and security-group boundary entirely.
- **Trade-off accepted:** tasks need an explicit egress path (NAT or VPC endpoints) to
  reach ECR/CloudWatch/SSM — this is exactly the design decision in `gate1-design.md`
  §3, and it's added complexity that a public-IP task wouldn't need.
- **Pillar:** Security.
- **Evidence:** the task's ENI has no associated public/Elastic IP (`describe-network-
  interfaces`); a direct `curl` to a task's private IP from outside the VPC times out;
  the service is only reachable end-to-end via the ALB.

## 3. Security-group references instead of IP allowlists

- **Risk reduced:** Fargate `awsvpc` ENIs are ephemeral — every task replacement gets a
  new private IP. A CIDR/IP allowlist would either go stale (breaking traffic after the
  next deployment) or, worse, keep a rule open for an IP that no longer belongs to the
  service it once did.
- **Trade-off accepted:** less immediately transparent than "read the IP off the rule" —
  reviewers need to understand the SG-to-SG reference model. SG references also only
  work within the same VPC, which is fine here but would be a real constraint if the
  architecture ever spanned VPCs.
- **Pillar:** Security, with a Operational Excellence angle (self-healing rules that
  don't need editing after every deploy).
- **Evidence:** force a Service A task replacement, confirm the new task gets a new
  private IP (`describe-tasks`), and confirm A↔B traffic keeps working with zero
  security-group edits.

## 4. Immutable image SHA (no `latest`)

- **Risk reduced:** non-reproducible deployments. `latest` can silently point to a
  different image than whatever was last tested, and rollback becomes guesswork instead
  of "redeploy the known-good SHA."
- **Trade-off accepted:** one more explicit step in every release — bump the declared
  SHA in IaC and run plan/review/apply — instead of pushing a new `latest` tag and
  letting ECS pick it up automatically.
- **Pillar:** Operational Excellence.
- **Evidence:** `terraform plan` diff shows exactly the task-definition `image` field
  changing from SHA A to SHA B; the ECS task-definition revision history shows discrete,
  named revisions; a rollback is just reverting the IaC variable to the prior SHA and
  applying — no image rebuild needed.

## 5. Remote, versioned and locked state

- **Risk reduced:** two engineers applying concurrently and corrupting or losing state;
  losing local state means losing the only record of what AWS resources IaC actually
  owns.
- **Trade-off accepted:** a bootstrap stack has to exist and be applied *before* any
  workload apply can run, and every apply now depends on S3/lock availability rather
  than a file on someone's laptop.
- **Pillar:** Operational Excellence (Reliability applied to the state data itself).
- **Evidence:** S3 bucket versioning shows multiple object versions after several
  applies; two concurrent `terraform apply` runs are attempted and the second visibly
  blocks on the lock until the first finishes; `terraform state list` output matches the
  actual AWS resources present in the account.
