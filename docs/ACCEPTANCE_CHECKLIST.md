# Acceptance Criteria Checklist — CI/CD for Containerized Microservices

Self-review completed 2026-07-03. Items marked [x] were verified locally by
running the exact commands the CI pipeline runs. Items that can only be proven
by a live GitHub Actions run / Docker Hub push are marked [~] with a note.

## A. Pull Request CI

- [x] Pull requests to main trigger CI (`on: pull_request: branches: [main]`)
- [x] Dependencies install successfully for each service (`pip install -r requirements-dev.txt`)
- [x] Tests run for each service — 2 tests per service, 6/6 passing locally
- [x] Build command runs where applicable (`python -m compileall .` compile check; Python has no bundling step)
- [x] Docker image builds locally for each service (matrix over service-a/b/c)
- [x] Failed tests or failed builds block merge (jobs are chained with `needs:`; publish never runs on PRs)

## B. Compose Verification

- [x] `docker compose config` passes
- [x] `docker compose -f docker-compose.prod.yml config` passes (validated in CI with dummy env)
- [x] `docker compose build --pull` succeeds
- [x] `docker compose up -d` starts the stack (4 containers Up)
- [x] Gateway health check passes (`curl --fail http://localhost:8080/service-a/health` → 200)
- [x] Stack is cleaned up after CI (`docker compose down -v` with `if: always()`)

## C. Image Publishing

- [x] Images are pushed only after merge/push to main (`if: github.event_name == 'push' && github.ref == 'refs/heads/main'`)
- [~] Images are pushed to Docker Hub — pipeline is complete; requires repo secrets on GitHub for a live run
- [x] Images use `sha-<short-commit-hash>` tags (`sha-${GITHUB_SHA::7}`)
- [x] Deployment docs do not use `latest`
- [x] Image labels include source repo and revision (`org.opencontainers.image.source` / `.revision`)

## D. Secrets and Environment Handling

- [x] `DOCKERHUB_TOKEN` is consumed as a GitHub Secret (`secrets.DOCKERHUB_TOKEN`)
- [x] `DOCKERHUB_USERNAME` is consumed as a GitHub Variable (`vars.DOCKERHUB_USERNAME`) and documented in README
- [x] No real `.env` file is committed (`.gitignore` + `.dockerignore` exclude it)
- [x] No API keys, passwords, tokens, or secrets are committed
- [x] `.env.example` documents required runtime variables (`DOCKERHUB_USERNAME`, `APP_NAME`, `IMAGE_TAG`)

## E. Dockerfile Quality

- [x] No Dockerfile uses `FROM image:latest`
- [x] Base images are version-pinned (`python:3.12-slim`, `nginx:1.27-alpine`)
- [x] Reproducible installs: pinned `requirements.txt` + `pip install --no-cache-dir` (Python equivalent of `npm ci`)
- [x] Dev/test dependencies (`pytest`, `httpx`) are split into `requirements-dev.txt` and are NOT installed in the image (equivalent of `npm ci --omit=dev`)
- [x] App runs as non-root (`USER appuser` — verified with `docker exec service-a whoami`)
- [x] `.dockerignore` present at repo root AND in each service build context (excludes tests, caches, env files)
- [x] Docker image does not include unnecessary build files (Dockerfile COPIES only `app.py`, `logger.py`, `requirements.txt`)
- [x] `EXPOSE` documents the intended service port (3001/3002/3003)

## F. Production Compose Readiness

- [x] `docker-compose.prod.yml` exists
- [x] Production Compose uses `image:` not `build:`
- [x] `IMAGE_TAG` controls the deployed version (`${DOCKERHUB_USERNAME}/${APP_NAME}-service-X:${IMAGE_TAG}`)
- [x] Only nginx exposes a host port (8080)
- [x] Internal services do not expose host ports (verified: `curl localhost:3002` refused; `/service-b/` via nginx → 403)
- [x] Backend network is separated and `internal: true`
- [x] Restart policies are configured (`unless-stopped` on all services)
- [x] Services read config from environment (`BIND_HOST`, `SERVICE_B_URL`, `SERVICE_C_URL`, `SERVICE_A_URL`) instead of hardcoded URLs

## G. Deployment Script

- [x] `scripts/deploy.sh` exists and is executable
- [x] Script accepts `sha-<commit>` as an argument
- [x] Script fails clearly when tag is missing (verified: usage message, exit 1)
- [x] Script fails clearly when `DOCKERHUB_USERNAME` is missing (verified: exit 1)
- [x] Script pulls images before starting services (`pull` → `up -d --remove-orphans` → `ps`)
- [x] Script uses `docker-compose.prod.yml`
- [x] Script does not hard-code `latest`

## Minimum Passing Standard

- [x] CI runs tests before Docker image build
- [x] CI builds application code before Docker image build
- [~] Docker images are pushed to Docker Hub (pipeline complete; needs live secrets)
- [x] Images use `sha-<commit>` tags
- [x] No real secrets are committed
- [x] Production Compose pulls images instead of building locally
- [x] Deployment script runs a specific image version
- [~] Saturday peer review — to be completed in-session

## Local Verification Evidence (2026-07-03)

```
pytest: 6/6 passed (service-a, service-b, service-c)
python -m compileall: OK for all three services
docker compose config: OK (dev and prod)
docker compose build --pull: 3 images built
docker compose up -d: 4 containers Up, only nginx published a host port
curl /service-a/health → 200 {"service":"service-a","status":"healthy",...}
curl /service-b/health via nginx → 403 (internal-only enforced)
Request trace grade-check-001 → same request_id in nginx, service-a,
  service-b, service-c logs, including the async callback_received event
docker exec service-a whoami → appuser (non-root)
./scripts/deploy.sh (no tag) → exit 1 with usage
./scripts/deploy.sh sha-abc1234 (no DOCKERHUB_USERNAME) → exit 1
```

Note: the yanked `requests==2.32.0` pin (conflicted with the CVE-2024-35195
fix) was bumped to `requests==2.32.3` in all requirements files.
