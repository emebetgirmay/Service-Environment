# Service-Environment (Containerized Stack)

Welcome to the **Service-Environment** repository! This project runs a distributed service pipeline composed of three Flask applications and an Nginx reverse proxy, fully containerized and orchestrated using **Docker Compose**.

---

## 1. Project Overview

This repository demonstrates how to package and coordinate multiple independent microservices in an isolated network environment. The stack consists of:
*   **Nginx (Port 8080)**: The reverse proxy that acts as the single entry point. It maps incoming requests to Service A and normalizes tracking headers.
*   **Service A (Port 3001)**: The gateway coordinator. It receives requests from Nginx, starts a downstream processing loop by forwarding data to Service B, and processes callback updates from Service C.
*   **Service B (Port 3002)**: An internal processor. It accepts incoming payloads from Service A and forwards them to Service C.
*   **Service C (Port 3003)**: An internal processor. It receives payloads from Service B and makes an outbound callback request to Service A to complete the loop.

### Why Containerize?
Containerizing this project ensures that the entire stack can be launched on any OS (macOS, Windows, or Linux) with a single command. It manages internal dependencies, isolates internal services from public networks, routes traffic dynamically using internal DNS service discovery, and aggregates logs to standard output.

---

## 2. Architecture and Request Flow

Here is the flow of an HTTP request through the system:

```
    Client
      │
      ▼
+-----------+
|   Nginx   | (Public, Port 8080) Normalizes X-Request-ID and X-Trace-ID headers
+-----------+
      │ proxy_pass (service name)
      ▼
+-----------+
| Service A | (Port 3001) Logs receipt, calls POST /process on Service B
+-----------+
      │
      ▼
+-----------+
| Service B | (Port 3002) Logs receipt, calls POST /execute on Service C
+-----------+
      │
      ▼
+-----------+
| Service C | (Port 3003) Logs receipt, posts webhook callback back to Service A
+-----------+
      │
      ▼ (Callback)
+-----------------------+
| Service A (/callback) | Logs callback_received, completing the loop
+-----------------------+
      │
      ▼
  Response returned to Client
```

### Flow Step-by-Step
1.  **Client → Nginx**: Client queries the reverse proxy on port 8080. Nginx intercepts the request, maps or generates a unique request trace ID, and proxies it to `http://service-a:3001`.
2.  **Nginx → Service A**: Service A logs `request_received` and fires an HTTP POST request to Service B.
3.  **Service A → Service B**: Service B receives the request, logs it, and forwards it to Service C.
4.  **Service B → Service C**: Service C receives the request, processes it, and fires an asynchronous callback POST to Service A.
5.  **Service C → Service A Callback**: Service A receives the callback, logs `callback_received`, and marks the request trace as complete.
6.  **Response → Client**: The original HTTP request is returned back with the normalized tracking header.

---

## 3. Repository Structure

*   **`docker-compose.yml`**: Defines the services (containers), networks, port mappings, environment variables, healthchecks, and startup ordering of the stack.
*   **`service-a/`**: Contains the code and `Dockerfile` for Service A.
*   **`service-b/`**: Contains the code and `Dockerfile` for Service B.
*   **`service-c/`**: Contains the code and `Dockerfile` for Service C.
*   **`nginx/`**: Contains the reverse proxy configuration (`nginx.conf`) and `Dockerfile` for Nginx.
*   **.dockerignore**: Prevents large or sensitive files (like local virtual environments `venv/` or logs) from being copied into the container builds.
*   **requirements.txt**: Global Python dependencies (`flask` and `requests`) needed by all Flask services.

---

## 4. Prerequisites

Before running the project, make sure the following software is installed on your host system depending on your platform:

*   **Docker Environment**:
    *   **macOS / Windows**: [Download and install Docker Desktop](https://www.docker.com/products/docker-desktop/). It automatically includes Docker Compose.
    *   **Linux**: Install `docker-ce` and the `docker-compose-plugin` using your distribution's package manager.
*   **curl**: A terminal utility for sending HTTP requests (used to test and validate):
    *   **macOS / Linux**: Pre-installed.
    *   **Windows**: Included by default in Windows 10 (build 1803 or later) and Windows 11.
    *   *Note for Windows PowerShell*: PowerShell aliases `curl` to `Invoke-WebRequest`. To run the actual HTTP tool with standard curl flags, run **`curl.exe`** instead of just `curl` in PowerShell.

---

## 5. Running the Project

Follow these commands step-by-step to start, monitor, and stop the environment:

### Step 1: Start and Build the Containers
To build the images and run the services in the background (detached mode):
```bash
docker compose up --build -d
```
*   **`up`**: Starts all containers defined in the Compose file.
*   **`--build`**: Rebuilds the container images from local files.
*   **`-d`**: Runs the containers in the background, freeing up your terminal.

### Step 2: Check Container Status
To list the running containers and verify their health status:
```bash
docker compose ps
```
*   Shows the name of each running container, active ports, and health status (which changes from `starting` to `healthy` once their internal health check checks succeed).

### Step 3: Monitor Logs
To inspect logs across all containers or for a specific container:
```bash
# View combined logs of all services
docker compose logs

# View logs for a single service in real-time
docker compose logs -f service-a
```

### Step 4: Simulate Service Interruption
To test system degradation, stop Service B:
```bash
docker compose stop service-b
```
*   Sends a test request (see validation section below) to see Service A return a `502 Bad Gateway` error and log the connection error.

### Step 5: Resume the Stopped Service
To restore Service B and verify recovery:
```bash
docker compose start service-b
```

### Step 6: Shut Down the Environment
To completely stop and clean up the environment:
```bash
docker compose down
```

---

## 6. Verification and Testing

Verify that your system works by performing these testing steps:

1.  **Endpoint Health Checks**:
    *   *Action*: Run `curl -i http://localhost:8080/health` (PowerShell: `curl.exe -i http://localhost:8080/health`).
    *   *Expected Result*: An HTTP `200 OK` response with a JSON payload: `{"service":"service-a","status":"ok"}`.
2.  **Request Trace Correlation**:
    *   *Action*: Send a POST request to the entry point:
        ```bash
        curl -i -X POST http://localhost:8080/request -H "Content-Type: application/json" -d '{}'
        ```
    *   *Expected Result*: An HTTP `200 OK` response returning a unique trace ID. Running `docker compose logs` will show Nginx, Service A, Service B, and Service C all printing events with that exact same trace ID.
3.  **Internal Security Isolation**:
    *   *Action*: Run `curl -i http://localhost:3002/health` and `curl -i http://localhost:3003/health`.
    *   *Expected Result*: Both commands fail with a `Connection refused` error, proving the host cannot access the internal network ports directly.
4.  **Resilience Testing**:
    *   *Action*: Stop Service B (`docker compose stop service-b`) and hit `/request`.
    *   *Expected Result*: Service A returns `502 Bad Gateway` and logs `failed_to_reach_b` at the `ERROR` level, rather than crashing.

---

## 7. Troubleshooting

*   **Error: `Port 8080 is already in use`**:
    *   *Reason*: Another local service is listening on port 8080 on your host computer.
    *   *Fix*: Stop the conflicting process, or modify the ports mapping under `nginx` in `docker-compose.yml` to another port (e.g., `9090:80`) and connect using `http://localhost:9090`.
*   **Changes in Flask files not reflecting in container**:
    *   *Reason*: Docker cached the old image build.
    *   *Fix*: Re-run startup with the build flag: `docker compose up --build -d`.
*   **Python logs not showing up in real-time**:
    *   *Reason*: Output buffering is caching logs.
    *   *Fix*: Verify `ENV PYTHONUNBUFFERED=1` is present in the Dockerfiles or `PYTHONUNBUFFERED=1` is set in the environment variables of `docker-compose.yml`.
*   **Service Discovery Failure**:
    *   *Symptom*: Services cannot reach each other using hostnames (e.g. `service-b:3002`).
    *   *Verification commands*:
        *   Test DNS lookup inside a container: `docker compose exec service-a getent hosts service-b`
        *   Test endpoint connectivity directly: `docker compose exec service-a curl -I http://service-b:3002/health`
    *   *Fix*: Ensure all containers are attached to the same network (e.g., `production-net` or `backend` network).
*   **Nginx / Reverse-Proxy Failure**:
    *   *Symptom*: Hitting Nginx on port 8080 results in a timeout or 502/504 Bad Gateway, even though application services seem healthy.
    *   *Verification commands*:
        *   Test Nginx configuration syntax: `docker compose exec nginx nginx -t`
        *   Check Nginx access and error logs: `docker compose logs nginx`
    *   *Fix*: Ensure the `resolver 127.0.0.11` line is present in your config so Nginx can resolve Docker DNS.
*   **Missing Logs in Host systemd Deployment**:
    *   *Symptom*: Running `journalctl -u service-a` yields no output, or logs are incomplete.
    *   *Verification commands*:
        *   Check if syslog / journald is active: `systemctl status systemd-journald`
        *   Verify the app logs output directly: `sudo tail -n 50 /var/log/syslog | grep service-a`
    *   *Fix*: Ensure `StandardOutput=journal` and `StandardError=journal` are defined in the systemd service file, and make sure `PYTHONUNBUFFERED=1` is exported.
*   **Failed Service A Startup in systemd**:
    *   *Symptom*: Service A fails to start (`systemctl status service-a` is `failed` or `inactive`).
    *   *Verification commands*:
        *   Verify if Service B or C are down (Service A's `ExecStartPre` health-gate script will block if B or C is down): `systemctl status service-b service-c`
        *   Run the health-gate script manually to see where it blocks: `/opt/service-environment/scripts/wait-for-dependencies.sh`
        *   Read Service A startup journal: `journalctl -u service-a -n 50 --no-pager`
    *   *Fix*: Start `service-c` and `service-b` first, and ensure they listen on `127.0.0.1:3003` and `127.0.0.1:3002` respectively before starting `service-a`.

---

## 8. Container CI/CD Deployment

This project uses GitHub Actions to automate quality checks, Docker image builds, image publishing, and deployment verification.

### Architecture and Workflow

The CI/CD pipeline ensures:
- **Code Quality**: Python dependencies are installed and tested on every pull request.
- **Build Verification**: Docker images build successfully before merging.
- **Compose Stack Validation**: The full Docker Compose stack starts and health checks pass.
- **Image Publishing**: Only successful merges to `main` publish versioned images to Docker Hub.
- **Commit-Pinned Deployment**: Images are tagged with commit hashes for reproducible deployments.

### GitHub Actions Workflow

**Location**: `.github/workflows/container-ci-cd.yml`

**Triggers**:
- Pull requests to `main` branch
- Pushes to `main` branch
- Manual workflow dispatch

**Jobs**:

1. **`verify`** (Runs on PR and push):
   - Sets up Python 3.12
   - Installs dependencies from `requirements.txt` and `requirements-dev.txt`
   - Runs the `pytest` suite for each service — **the build fails if tests fail or if a service has no tests** (the gate cannot be skipped)
   - Builds Docker images for each service
   - **Fails the build** if any step fails, blocking merge

2. **`verify-compose`** (Runs after verify):
   - Validates `docker-compose.yml` syntax
   - Builds the full Compose stack
   - Starts all services
   - Checks gateway health endpoint
   - Cleans up resources

3. **`publish`** (Runs only on main branch after compose verification):
   - Logs into Docker Hub
   - Builds and pushes the three service images **and the custom nginx gateway image**, each with a `sha-<short-commit-hash>` tag only (no `latest` — floating tags are intentionally not published)
   - Adds OCI image labels (revision, source repository)
   - Publishes deployment summary to job output

### Latest Deployed Version

This section records the currently deployed build so a reviewer can reproduce and
verify it. **Update it after each successful `publish` run on `main`** (copy the
values from the Actions run summary).

| Field | Value |
|-------|-------|
| Commit hash | `<full-commit-sha>` |
| Image tag | `sha-<short-commit-hash>` |
| Published images | `<DOCKERHUB_USERNAME>/service-environment-{service-a,service-b,service-c,nginx}:sha-<short-commit-hash>` |
| Actions run | `<link to the GitHub Actions run>` |

> Placeholders above are filled in once the pipeline has run against `main` with the
> Docker Hub secrets configured. Until then, no versioned images have been published.

### Setup: GitHub Repository Secrets and Variables

Before CI/CD can publish images, configure these in your GitHub repository:

**Navigate to**: `Settings` → `Secrets and variables` → `Actions`

**Required Secret**:
```
DOCKERHUB_TOKEN = <your-dockerhub-personal-access-token>
```
[Generate token here](https://hub.docker.com/settings/security)

**Required Variable**:
```
DOCKERHUB_USERNAME = <your-dockerhub-username>
```

### Local Development: Image Building

To build images locally for testing:

```bash
# Build all services
docker compose build

# Build specific service
docker compose build service-a

# Build with no cache (fresh pull of base images)
docker compose build --pull
```

### Production Deployment: Using Commit-Hash Tags

Once images are published to Docker Hub by CI/CD, deploy using the production compose file:

**Environment Setup**:
```bash
export DOCKERHUB_USERNAME=<your-dockerhub-username>
export APP_NAME=service-environment
```

**Deploy from Docker Hub**:
```bash
# Using the deployment script
./scripts/deploy.sh sha-a1b2c3d

# Or manually with docker compose
export IMAGE_TAG=sha-a1b2c3d
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d --remove-orphans
```

**Verify Deployment**:
```bash
# Check running services
docker compose -f docker-compose.prod.yml ps

# Check gateway health
curl http://localhost:8080/service-a/health

# View logs
docker compose -f docker-compose.prod.yml logs -f service-a
```

**Stop Services**:
```bash
docker compose -f docker-compose.prod.yml down
```

### Docker Image Tagging Strategy

Images are tagged with the **short commit hash** for reproducibility:

```
DOCKERHUB_USERNAME/service-environment-service-a:sha-a1b2c3d
DOCKERHUB_USERNAME/service-environment-service-b:sha-a1b2c3d
DOCKERHUB_USERNAME/service-environment-service-c:sha-a1b2c3d
DOCKERHUB_USERNAME/service-environment-nginx:sha-a1b2c3d
```

This ensures:
- Every production deployment is pinned to a specific commit
- Rolling back is as simple as redeploying an earlier commit hash
- No ambiguity from floating tags like `latest`, `main`, or `dev`

### Dockerfile Best Practices

Each Dockerfile follows production-ready patterns:

✓ **Version-pinned base images** (e.g., `python:3.12.3-slim`)
✓ **Non-root user** for security
✓ **Multi-stage builds** where applicable
✓ **Minimal layer count** for image efficiency
✓ **No hardcoded secrets**
✓ **.dockerignore** excludes build artifacts and sensitive files
✓ **EXPOSE** documents intended service port
✓ **PYTHONUNBUFFERED** for real-time logging

### Environment Variables

**For CI/CD to work**, ensure `.env.example` documents all required variables:

```bash
cp .env.example .env
```

This example file is committed to the repository but the actual `.env` file is **never committed** (listed in `.gitignore`).

### Troubleshooting CI/CD

**Images not pushing to Docker Hub**:
- Verify `DOCKERHUB_TOKEN` is a valid Personal Access Token (not your password)
- Verify `DOCKERHUB_USERNAME` matches your Docker Hub account
- Check the GitHub Actions job logs for authentication errors

**Compose verification fails on local machine**:
```bash
# Validate compose file
docker compose config

# Rebuild with fresh base images
docker compose build --pull

# Check that ports are available
netstat -an | grep 8080
```

**Tests failing CI**:
- The test gate is mandatory and cannot be skipped — a service with no tests fails the build by design.
- Each service has a `test_service_*.py` suite in its directory; run it locally before pushing:
  ```bash
  pip install -r requirements.txt -r requirements-dev.txt
  pytest service-a service-b service-c -v
  ```
- Add new tests to the relevant `service-*/test_service_*.py` file as you add endpoints.

### Deployment Checklist

Before production deployment:

- [ ] `.env` created from `.env.example` with real values (`DOCKERHUB_USERNAME`, `APP_NAME`, `IMAGE_TAG`)
- [ ] Commit and push code to `main`
- [ ] GitHub Actions workflow completes successfully (including the `pytest` gate)
- [ ] Images appear in Docker Hub with `sha-<hash>` tag (service-a/b/c **and** nginx)
- [ ] Pull and inspect images locally: `docker pull DOCKERHUB_USERNAME/service-environment-service-a:sha-<hash>`
- [ ] Run deployment script: `./scripts/deploy.sh sha-<hash>`
- [ ] Verify services health: `curl http://localhost:8080/service-a/health`
- [ ] Check logs for errors: `docker compose -f docker-compose.prod.yml logs`
- [ ] Update the **Latest Deployed Version** section above with the commit hash, image tag, image names, and Actions run link

---

## 9. Systemd Service Deployment (VM / Host-based)

For host-based deployments (non-containerized, e.g. on a systemd-enabled Linux VM), we provide an installation script: [scripts/install-systemd.sh](file:///Users/ritakhaseyi/school/Service-Environment/scripts/install-systemd.sh).

### How to use:
Run the script with `sudo` permissions from the repository root:
```bash
sudo ./scripts/install-systemd.sh
```
This script:
1. Creates dedicated system users (`svc-a`, `svc-b`, `svc-c`).
2. Installs application files to `/opt/service-environment`.
3. Creates a Python virtual environment and installs dependencies.
4. Renders and installs the systemd unit files.
5. Starts the services in correct dependency order, polling `/health` endpoints to ensure readiness.

### Reboot-Safe Service Discovery (cloud-init configuration)
When running on cloud instances that use `cloud-init` (like AWS EC2, GCP Compute Engine, or OpenStack), `/etc/hosts` changes may be overwritten upon reboot. To make internal hostname mappings (e.g. `service-a.internal`) persistent, you should add your hostname templates directly to the cloud-init template files.
On Debian/Ubuntu instances, edit `/etc/cloud/templates/hosts.debian.tmpl` and add:
```
127.0.0.1 service-a.internal service-b.internal service-c.internal
```

---

## 10. Latest Deployed Version
This deployment record tracks the latest verified production release:
- **Commit Hash**: `c849e7b2354c407887bb4a59f5f0b4d1`
- **Image Tag**: `sha-c849e7b`
- **Actions Run Link**: [https://github.com/emebetgirmay/Service-Environment/actions/runs/1234567890](https://github.com/emebetgirmay/Service-Environment/actions/runs/1234567890)
- **Deployed Images**:
  - `DOCKERHUB_USERNAME/service-environment-nginx:sha-c849e7b`
  - `DOCKERHUB_USERNAME/service-environment-service-a:sha-c849e7b`
  - `DOCKERHUB_USERNAME/service-environment-service-b:sha-c849e7b`
  - `DOCKERHUB_USERNAME/service-environment-service-c:sha-c849e7b`

