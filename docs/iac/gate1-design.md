# Gate 1 — Design Before Creation

**Assignment:** Greenfield ECS Fargate with Terraform/OpenTofu
**Group:** 9
**Region:** eu-north-1 (assigned — no other Region may be used)
**Status:** DRAFT — pending peer/instructor review. No workload resources exist yet.
**Owners at time of writing:** solo draft (Service A/B/C, Platform, and Release ownership
not yet assigned by the group — see [Ownership map](#ownership-map) for placeholders to
fill in once roles are rotated).

This document is the Gate 1 submission required before the first workload `apply`. It
covers: dependency graph and ownership map, CIDR/subnet-capacity table, route-table and
egress design, security-group matrix and traffic contract, expected resource names and
tags, three predicted broken dependency edges, state-backend design, and
application-release ownership. The five architecture decision cards are in a companion
file, [`docs/iac/gate1-decision-cards.md`](./gate1-decision-cards.md).

---

## 1. Dependency graph and ownership map

### Request-path dependency graph

```
                         Internet
                            │
                            ▼
                    ┌───────────────┐
                    │  Internet GW  │  (platform)
                    └───────────────┘
                            │
                            ▼
        ┌───────────────────────────────────────┐
        │   ALB (public subnets, 2 AZs) :80      │  (platform)
        │   sg-alb                               │
        └───────────────────────────────────────┘
                            │ :3001  (target group, type=ip)
                            ▼
        ┌───────────────────────────────────────┐
        │   Service A  (private subnets, 2 AZs)  │  (service-a owner)
        │   sg-svc-a · desired=2                 │
        └───────────────────────────────────────┘
                            │ :3002  service-b.group9.internal
                            ▼
        ┌───────────────────────────────────────┐
        │   Service B  (private subnets, 2 AZs)  │  (service-b owner)
        │   sg-svc-b · desired=1                 │
        └───────────────────────────────────────┘
                            │ :3003  service-c.group9.internal
                            ▼
        ┌───────────────────────────────────────┐
        │   Service C  (private subnets, 2 AZs)  │  (service-c owner)
        │   sg-svc-c · desired=1                 │
        └───────────────────────────────────────┘
                            │ :3001 /callback  ⚠ see Predicted Edge #1
                            └────────────────► back to Service A
```

Service Connect namespace `group9.internal` (platform-owned) backs the `service-b` /
`service-c` DNS names above. Service A is the only service registered against the ALB
target group; B and C are reachable only via Service Connect inside the mesh.

### Ownership map

| Area | AWS / IaC resources owned | Owner (role) | Owner (person) |
|---|---|---|---|
| Platform | VPC, subnets, route tables, IGW, VPC endpoints, ECS cluster, Service Connect namespace, ALB + listener, shared IAM (task execution role), backend wiring in `infra/environments/lab` | Platform owner | *unassigned — solo draft* |
| Service A | ECR repo, module inputs, task definition, log group, `sg-svc-a`, ECS service, ALB target-group registration, release evidence | Service A owner | *unassigned — solo draft* |
| Service B | ECR repo, module inputs, task definition, log group, `sg-svc-b`, ECS service, release evidence | Service B owner | *unassigned — solo draft* |
| Service C | ECR repo, module inputs, task definition, log group, `sg-svc-c`, ECS service, release evidence | Service C owner | *unassigned — solo draft* |
| Release | Plan summaries, approval evidence, image-SHA selection, runtime release proof, rollback evidence | Release owner | *unassigned — solo draft* |

Action item once the group assigns names: replace the `*unassigned*` cells and rotate
Platform/Release between cycles per the assignment rules for 3-person teams.

---

## 2. CIDR and subnet-capacity table

VPC CIDR uses the group number in the second octet so groups never collide if state or
peering is ever compared side by side: **`10.9.0.0/16`**.

| Subnet | AZ | CIDR | Usable IPs (AWS reserves 5) | Purpose |
|---|---|---|---|---|
| `devops-g9-public-a` | eu-north-1a | `10.9.0.0/24` | 251 | ALB ENIs |
| `devops-g9-public-b` | eu-north-1b | `10.9.1.0/24` | 251 | ALB ENIs |
| `devops-g9-private-app-a` | eu-north-1a | `10.9.10.0/24` | 251 | Fargate tasks (A/B/C) |
| `devops-g9-private-app-b` | eu-north-1b | `10.9.11.0/24` | 251 | Fargate tasks (A/B/C) |

Reserved, unallocated ranges for future growth without re-addressing: `10.9.2.0/24`–
`10.9.9.0/24` (public / a possible third AZ), `10.9.12.0/24`–`10.9.19.0/24` (private).

### Rolling-deployment headroom

Each Fargate task consumes exactly one ENI/IP in its subnet (`awsvpc` mode).

- **Steady state:** desired counts A=2, B=1, C=1 → 4 ENIs total, spread across 2 AZs by
  the ECS scheduler → ~2 ENIs/subnet.
- **During a rolling deployment** (circuit breaker + default `maximumPercent=200`,
  `minimumHealthyPercent=100`): the service being deployed can transiently **double**.
  Process discipline (routine plan note, one change at a time) means only one service
  deploys at a time in practice:
  - Deploying A: up to 4 A-tasks momentarily (2 old + 2 new) instead of 2 → worst-case
    subnet load ≈ 2 extra A + steady B(1) + C(1) ≈ 4–5 ENIs in one subnet.
  - Hypothetical worst case (all three deploying at once, which the routine-plan
    process is designed to prevent): A=4, B=2, C=2 = 8 ENIs total ≈ 4–5/subnet.
- Either way, peak usage is **under 2%** of a /24's 251 usable IPs. A `/24` per subnet
  gives >10x headroom on desired-count growth before any re-addressing is needed.

---

## 3. Route-table and egress design

| Route table | Associated with | Routes |
|---|---|---|
| `devops-g9-rt-public` | both public subnets | `10.9.0.0/16` → local; `0.0.0.0/0` → Internet Gateway |
| `devops-g9-rt-private` | both private-app subnets | `10.9.0.0/16` → local; S3 prefix-list → S3 gateway endpoint (auto-added on association). **No `0.0.0.0/0` route — no NAT Gateway.** |

### Egress decision: VPC endpoints instead of a NAT Gateway

Reviewed `service-a/app.py`, `service-b/app.py`, `service-c/app.py`: the only outbound
`requests.post()` calls are A→B, B→C, and C→A — all internal, Service-Connect-resolved
calls. No service makes a call to a third-party/public API. Fargate tasks otherwise only
need to reach AWS control-plane services (image pull, log shipping, ECS Exec), which can
all be satisfied without any path to the public internet:

| Endpoint | Type | Purpose |
|---|---|---|
| `com.amazonaws.eu-north-1.ecr.api` | Interface | ECR auth/API calls |
| `com.amazonaws.eu-north-1.ecr.dkr` | Interface | Image layer pull |
| `com.amazonaws.eu-north-1.s3` | Gateway (free, route-table based) | ECR backs image layers with S3 |
| `com.amazonaws.eu-north-1.logs` | Interface | CloudWatch Logs shipping |
| `com.amazonaws.eu-north-1.ssmmessages` | Interface | ECS Exec channel |
| `com.amazonaws.eu-north-1.ec2messages` | Interface | ECS Exec channel |
| `com.amazonaws.eu-north-1.ssm` | Interface | ECS Exec channel |

Interface endpoints live in the private-app subnets behind a dedicated `sg-vpce`
security group, allowing inbound `:443` only from `sg-svc-a`/`sg-svc-b`/`sg-svc-c`.

**Trade-off, flagged explicitly:** if a future service needs to call a real external
API, it will fail silently (connection timeout, no NAT path) until the team adds either
a NAT Gateway or another AWS-service-specific endpoint. This is an accepted, documented
constraint, not an oversight — revisit if scope grows. This choice doubles as the
group's Cost-Aware Design badge candidate (no NAT Gateway = no hourly + per-GB NAT
charge in a lab environment that's destroyed/rebuilt three times).

---

## 4. Security-group matrix and traffic contract

All rules reference security groups (never CIDRs/task-IP allowlists) per the assignment
requirement.

| Rule | Source SG | Destination SG : port | Direction | Result | Traffic-contract row |
|---|---|---|---|---|---|
| SG-1 | `0.0.0.0/0` | `sg-alb` : 80 | inbound on ALB | **Allow** | Internet → ALB port 80 |
| SG-2 | `sg-alb` | `sg-svc-a` : 3001 | inbound on Service A | **Allow** | ALB SG → Service A app port |
| SG-3 | `sg-svc-a` | `sg-svc-b` : 3002 | inbound on Service B | **Allow** | Service A SG → Service B internal port |
| SG-4 | `sg-svc-b` | `sg-svc-c` : 3003 | inbound on Service C | **Allow** | Service B SG → Service C internal port |
| SG-5 | *(no rule created)* | `sg-svc-a`/`sg-svc-b`/`sg-svc-c` | inbound from `0.0.0.0/0` | **Deny (implicit)** | Internet → Services A/B/C directly |
| SG-6 | *(no rule created)* | `sg-svc-c` from `sg-svc-a` | inbound on Service C | **Deny (implicit)** | Service A → Service C |
| SG-7 ⚠ | `sg-svc-c` | `sg-svc-a` : 3001 (`/callback`) | inbound on Service A | **Open question — see Predicted Edge #1** | *not in the assignment's traffic-contract table* |
| Egress | `sg-svc-a`/`b`/`c` | `sg-vpce` : 443 + each other per rows above | outbound | **Allow (scoped)** | not a contract row — least-privilege choice, see below |

**Egress note:** AWS security groups default to allow-all egress. This design
deliberately restricts egress on the three service SGs to only `sg-vpce:443` plus the
specific downstream service port each one calls, rather than accepting the wide-open
default. This is stricter than the assignment strictly requires — called out here so the
group can consciously accept or relax it, not inherit it silently.

---

## 5. Expected resource names and tags

**Naming convention:** every resource begins with `devops-g9-`, with one explicit
exception the assignment itself mandates: the Service Connect namespace must be the
literal string `group9.internal`, not `devops-g9-`-prefixed, because the spec requires
that exact DNS-namespace format.

**Tags applied to every resource** (except where an AWS resource type doesn't support
tagging):

| Tag | Value |
|---|---|
| `project` | `service-environment` |
| `group` | `g9` |
| `owner` | one of `platform` / `service-a` / `service-b` / `service-c` / `release` — matches the [ownership map](#ownership-map) |
| `environment` | `lab` |

**Expected resource names:**

| Resource | Name |
|---|---|
| VPC | `devops-g9-vpc` |
| Internet Gateway | `devops-g9-igw` |
| Public subnets | `devops-g9-public-a`, `devops-g9-public-b` |
| Private app subnets | `devops-g9-private-app-a`, `devops-g9-private-app-b` |
| Public route table | `devops-g9-rt-public` |
| Private route table | `devops-g9-rt-private` |
| VPC endpoints | `devops-g9-vpce-ecr-api`, `devops-g9-vpce-ecr-dkr`, `devops-g9-vpce-s3`, `devops-g9-vpce-logs`, `devops-g9-vpce-ssmmessages`, `devops-g9-vpce-ec2messages`, `devops-g9-vpce-ssm` |
| VPC-endpoint security group | `devops-g9-sg-vpce` |
| ALB | `devops-g9-alb` |
| ALB security group | `devops-g9-sg-alb` |
| ALB target group | `devops-g9-tg-service-a` |
| ECS cluster | `devops-g9-cluster` |
| Service Connect namespace | `group9.internal` *(exception — see above)* |
| Service security groups | `devops-g9-sg-svc-a`, `devops-g9-sg-svc-b`, `devops-g9-sg-svc-c` |
| ECS services | `devops-g9-svc-a`, `devops-g9-svc-b`, `devops-g9-svc-c` |
| Task-definition families | `devops-g9-td-service-a`, `devops-g9-td-service-b`, `devops-g9-td-service-c` |
| CloudWatch log groups | `/ecs/devops-g9/service-a`, `/ecs/devops-g9/service-b`, `/ecs/devops-g9/service-c` |
| ECR repositories | `devops-g9-service-a`, `devops-g9-service-b`, `devops-g9-service-c` |
| Shared ECS task-execution role | `devops-g9-ecs-task-execution-role` |
| Per-service task roles | `devops-g9-ecs-task-role-service-a`, `-service-b`, `-service-c` |
| State bucket (bootstrap) | `devops-g9-tfstate-<account-id>` |
| State lock table (bootstrap, if not using S3-native locking) | `devops-g9-tflock` |

---

## 6. Predicted broken dependency edges

### Edge 1 — Service C → Service A callback is not in the traffic contract

The existing application (`service-c/app.py` → `SERVICE_A_URL` →
`http://service-a:3001/callback`) closes the loop by having C call back to A directly.
The assignment's traffic contract only defines Internet→ALB, ALB→A, A→B, B→C, and denies
Internet→{A,B,C} and A→C — it says nothing about C→A. Without an explicit SG-7 rule
(above), this callback will be blocked by the implicit deny.

- **User symptom:** the client's original request to `/request` still gets a response
  (the forward chain A→B→C completes), but Service A's `/callback` never fires — no
  functional error surfaces to the caller, only an incomplete server-side trace.
- **AWS evidence:** VPC Flow Logs show a `REJECT` record for `sg-svc-c → sg-svc-a:3001`;
  Service C's CloudWatch log group shows a `failed_to_callback_a` ERROR event
  (connection timeout); Service A's CloudWatch log group never shows a matching
  `callback_received` event for that `trace_id`.
- **Decision needed before Gate 1 sign-off:** either (a) add SG-7 as an explicit allow
  rule and get instructor sign-off that it's a legitimate contract extension, or (b)
  change the release to remove the synchronous callback so the deployed architecture
  matches the contract exactly as written. Recommend flagging this to Robert directly —
  it's a real mismatch between the existing app and the assignment's traffic contract,
  not a mistake in this document.

### Edge 2 — ECS Exec fails silently under the no-NAT egress design

Because Section 3 chose VPC endpoints over a NAT Gateway, ECS Exec depends on the
`ssmmessages`/`ec2messages`/`ssm` interface endpoints existing and being reachable. If
one is missing or its security group doesn't allow the task's SG on :443:

- **User symptom:** `aws ecs execute-command` hangs, or fails with "The execute command
  failed because execute command was not enabled or the execute-command agent could not
  be reached."
- **AWS evidence:** `aws ecs describe-tasks` shows the task's `managedAgents` entry for
  `ExecuteCommandAgent` in a non-`RUNNING` status; `aws ec2 describe-vpc-endpoints`
  confirms whether the three SSM endpoints exist; this is a DNS/endpoint-availability
  failure, not a flow-log reject, so VPC Flow Logs will show nothing useful here — the
  absence of a Flow Log signal is itself part of the diagnostic evidence.

### Edge 3 — Service Connect proxy reachability looks fine on paper but isn't

Service Connect injects a local proxy (sidecar) into each task; the security-group rule
between `sg-svc-a` and `sg-svc-b` must allow the actual port Service Connect uses to
reach the upstream, not just the application's declared port, or DNS will resolve but
the connection will be refused.

- **User symptom:** Service A logs `failed_to_reach_b` even though the SG-3 rule "looks"
  correct on paper.
- **AWS evidence:** `aws ecs execute-command` into the Service A container and run
  `curl -v http://service-b.group9.internal:3002` — compare a DNS-resolves-but-refused
  result against `aws servicediscovery discover-instances` output for the namespace to
  confirm whether the failure is registration-side or security-group-side.

---

## 7. State-backend design

- **Bootstrap stack** (`infra/bootstrap/`, applied once, separately from the workload)
  creates:
  - S3 bucket `devops-g9-tfstate-<account-id>` (name includes account ID for global
    uniqueness) — versioning **on**, default encryption **on**, all four Public Access
    Block settings **on**, bucket policy denies non-TLS (`aws:SecureTransport: false`)
    requests.
  - Locking: prefer S3-native locking (`use_lockfile = true`, requires Terraform ≥1.10 /
    an equivalent OpenTofu release) so no second stateful resource is needed. If the
    group's pinned CLI version doesn't support it, fall back to a DynamoDB table
    `devops-g9-tflock` (`PAY_PER_REQUEST`, partition key `LockID`).
- **Bootstrap's own state** is kept local to the operator who runs it, on purpose — never
  stored inside the bucket it creates (avoids a chicken-and-egg problem and keeps the
  bootstrap's state out of the workload's blast radius). It's a rarely-run, single-owner
  operation; the bucket/lock-table names and IDs get recorded in this repo's
  `infra/bootstrap/README.md` output, not the state file itself.
- **Workload backend** (`infra/environments/lab/`) points at: `bucket =
  devops-g9-tfstate-<account-id>`, `key = lab/workload.tfstate`, `region = eu-north-1`,
  `use_lockfile = true` (or `dynamodb_table = devops-g9-tflock`).
- **Backend excluded from workload destruction:** the bucket and lock table live in a
  separate root module/state from `infra/environments/lab/`, so `terraform destroy` run
  against the workload state can never touch them.
- **No local state as source of truth:** every workload `plan`/`apply` goes through the
  S3 backend; `.terraform.lock.hcl` is committed, `*.tfstate` is git-ignored (done in
  this change).

---

## 8. Application-release ownership

```
Application change
  → tests (existing pytest suite, per service)
  → build SHA-tagged image           ┐
  → push to ECR                      │  image pipeline (CI) — build & publish authority
                                      ┘
  → update declared image SHA in IaC ┐
  → plan → review → apply            │  IaC (Release owner + service owner) — select & deploy authority
  → ECS rolling deployment           │
  → new SHA visible through ALB      ┘
```

- The **image pipeline** (extends the existing `.github/workflows/container-ci-cd.yml`)
  builds and pushes a Git-SHA-tagged image to each service's ECR repo
  (`devops-g9-service-a:<sha>`, etc.) on every merge to `main`. It never touches
  Terraform/OpenTofu state and never applies infrastructure changes.
- **IaC** declares which already-published SHA is deployed via a per-service module
  input (e.g. `service_a_image_tag`). Changing that value is a reviewed, versioned Git
  change made by the Release owner (in coordination with the relevant service owner) —
  never inferred from "whatever the pipeline most recently built."
- This split means CI has *build* authority and IaC has *deploy* authority — pushing an
  image never deploys it by itself, and `terraform plan` output stays meaningful (only
  the intended service's task-definition revision changes, not a surprise redeploy of
  all three).
- `latest` is rejected by construction — every declared tag must match an
  immutable-SHA/digest format (this is also the group's Immutable Release badge
  candidate; see decision card 4 in the companion file for the validation approach).

---

## Open items before this Gate 1 is ready to submit for review

1. **Resolve Edge 1** — decide with Robert whether SG-7 (C→A callback) is an approved
   contract extension or whether the app needs to drop the synchronous callback.
2. **Fill in the ownership map** — replace the `*unassigned*` placeholders once the group
   assigns Service A/B/C, Platform, and Release owners (and plan the rotation for Cycle
   2/3 if this is a 3-person team).
3. Confirm the group's Terraform vs OpenTofu choice and the exact CLI/provider versions
   to pin (not yet decided in this draft).
