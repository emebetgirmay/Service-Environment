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
