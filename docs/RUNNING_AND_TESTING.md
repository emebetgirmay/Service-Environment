# Running and Testing Guide

Welcome to the **Running and Testing Guide**! This guide is written specifically for students and beginners to help you run, test, and troubleshoot this containerized application stack. 

---

## 1. What This Project Is

This project is a multi-service application consisting of:
*   **Nginx**: A reverse proxy that acts as the front door.
*   **Service A**: The coordinator service.
*   **Service B**: An internal processor.
*   **Service C**: An internal processor that sends a callback.

### The Request Flow
When a request is made, it moves through the system in a loop:
1.  **Client** sends a request to Nginx.
2.  **Nginx** forwards the request to **Service A**.
3.  **Service A** logs the receipt of the request and sends a request to **Service B**.
4.  **Service B** logs the receipt of the request and sends a request to **Service C**.
5.  **Service C** logs the receipt of the request, makes a POST request to **Service A's callback** endpoint, and then responds to **Service B**.
6.  **Service A** receives the callback from Service C and logs `callback_received`.
7.  **Service B** receives the success response from Service C, logs `forwarded_to_c`, and responds to **Service A**.
8.  **Service A** receives the success response from Service B, logs `forwarded_to_b`, and responds to **Nginx**.
9.  **Nginx** responds to the **Client**.

### Why Docker Compose is Used
Docker Compose allows us to define and run this multi-container application with a single configuration file (`docker-compose.yml`). Instead of launching every service manually, setting up systemd services, modifying `/etc/hosts` for routing, and managing host-level firewalls, Docker Compose handles the startup, virtual networking, name resolution, and resource cleanup automatically.

---

## 2. What This Assignment is Asking Me to Do

Your lecturer wants to see that you can transition an application from a VM-style deployment (using systemd services and local hosts-file mapping) to a containerized deployment using Docker Compose.

### What You Are Being Graded On:
1.  **Correct Dockerfiles**: Using lightweight base images (`python:3.12-slim` and `nginx:alpine`).
2.  **Network Isolation**: Only Nginx is exposed to your host machine. Services A, B, and C must be internal-only and unreachable from the host.
3.  **Service Discovery**: Services must resolve and communicate with each other using their Docker Compose service names (e.g. `http://service-b:3002/process`).
4.  **Request Tracing**: A unique tracking ID (`X-Request-ID` or `X-Trace-ID`) must propagate through every hop in the loop.
5.  **Logging**: All container logs must write directly to `stdout`/`stderr` so they can be viewed via `docker compose logs`.
6.  **Resilience**: Graceful error handling and recovery when a service is temporarily stopped.

---

## 3. Prerequisites

Before starting, make sure you have the following installed on your host system:

1.  **Docker Environment**:
    *   **macOS / Windows**: Download and install **Docker Desktop** from [Docker's website](https://www.docker.com/products/docker-desktop/). This bundles the Docker Engine, GUI Dashboard, and `docker compose` command-line utility.
    *   **Linux (Ubuntu/Debian/CentOS)**: Install the Docker Engine and the Docker Compose plugin using your distribution's package manager. For example:
        ```bash
        sudo apt update
        sudo apt install docker-ce docker-compose-plugin
        ```
2.  **curl (Command Line Web Client)**:
    *   **macOS / Linux**: Pre-installed. Open your terminal and type `curl --version` to check.
    *   **Windows**: Included by default in Windows 10 (version 1803 and later) and Windows 11.
    *   *Critical PowerShell Note*: In Windows PowerShell, the command `curl` is a built-in alias for `Invoke-WebRequest` (which has completely different flags). To run the standard web client tool with the flags listed in this guide, you **MUST** run **`curl.exe`** instead of `curl`. For example, use: `curl.exe -i http://localhost:8080/health`.

---

## 4. How to Build and Run the Project

Below is a reference list of Compose commands you will use:

### A. Start the Stack (`docker compose up --build -d`)
*   **What it does**: Reads `docker-compose.yml`, builds local Docker images, sets up the network, and launches the containers in the background.
*   **When to use**: The first time you start the project, or whenever you edit a `Dockerfile` or source code.
*   **Command**:
    ```bash
    docker compose up --build -d
    ```

### B. View Container Status (`docker compose ps`)
*   **What it does**: Lists all containers managed by the Compose file and shows if they are running and if their health checks pass.
*   **When to use**: To check if your containers started successfully and are healthy.
*   **Command**:
    ```bash
    docker compose ps
    ```

### C. View Application Logs (`docker compose logs`)
*   **What it does**: Prints log output from all services to your console.
*   **When to use**: To trace request flow, inspect issues, or verify log formats.
*   **Commands**:
    ```bash
    # View combined logs of all containers
    docker compose logs
    
    # View logs for a single service and follow live updates
    docker compose logs -f service-a
    ```

### D. Stop a Single Container (`docker compose stop <service-name>`)
*   **What it does**: Pauses a container process safely without removing the container or network.
*   **When to use**: To simulate a service failure (e.g. stopping Service B).
*   **Command**:
    ```bash
    docker compose stop service-b
    ```

### E. Start a Stopped Container (`docker compose start <service-name>`)
*   **What it does**: Resumes a stopped container.
*   **When to use**: To verify recovery after simulating a failure.
*   **Command**:
    ```bash
    docker compose start service-b
    ```

### F. Tear Down the Stack (`docker compose down`)
*   **What it does**: Stops all containers, removes them, and deletes the virtual bridge network.
*   **When to use**: When you are done working and want to free up system memory and ports.
*   **Command**:
    ```bash
    docker compose down
    ```

---

## 5. Assignment Testing Guide

Run the following test scenarios to verify assignment compliance.

### Test 1: Starting the Project and Verifying Containers
*   **Purpose**: Verify the stack builds and runs without errors.
*   **Command**:
    ```bash
    docker compose up --build -d && docker compose ps
    ```
*   **What Success Looks Like**: All four services (nginx, service-a, service-b, service-c) are listed as `running` and their status shows `healthy`.
*   **What to check if it fails**: Run `docker compose logs` to check for container startup errors.

### Test 2: Verifying Only Nginx is Publicly Accessible
*   **Purpose**: Verify that the host can only access Nginx.
*   **Command**:
    ```bash
    curl -i http://localhost:8080/health
    ```
*   **What Success Looks Like**: An HTTP `200 OK` response with a JSON payload: `{"service":"service-a","status":"ok"}`.
*   **What to check if it fails**: Check Nginx configuration by running `docker compose logs nginx`.

### Test 3: Verifying Services B and C are Internal Only
*   **Purpose**: Verify that internal ports are not exposed to the host machine.
*   **Commands**:
    ```bash
    curl -i http://localhost:3002/health
    curl -i http://localhost:3003/health
    ```
*   **What Success Looks Like**: Both commands return a connection error (e.g., `curl: (7) Failed to connect to localhost port 3002: Connection refused`).
*   **What to check if it fails**: Check your `docker-compose.yml`. Make sure there is no `ports` section under `service-b` or `service-c`.

### Test 4: Verifying Request Tracing and Logging
*   **Purpose**: Trace a single request ID end-to-end through Nginx and all Python services.
*   **Command**:
    ```bash
    curl -i -X POST http://localhost:8080/request -H "Content-Type: application/json" -d '{"test": "tracing"}'
    ```
*   **What Success Looks Like**:
    1.  The curl response contains an `X-Request-ID` header (e.g. `X-Request-ID: abc-123-xyz`).
    2.  Run `docker compose logs | grep <your-request-id>`. You should see logs from Nginx, Service A, Service B, and Service C all sharing that exact trace ID.
*   **What to check if it fails**: Ensure Nginx's `nginx.conf` has the proxy headers configured and that Python services retrieve and forward the headers correctly.

### Test 5: Verifying Failure and Graceful Recovery
*   **Purpose**: Verify that stopping a dependency does not crash Service A, and that Service A handles the degradation gracefully.
*   **Commands**:
    ```bash
    # Stop Service B
    docker compose stop service-b
    
    # Send a request
    curl -i -X POST http://localhost:8080/request -H "Content-Type: application/json" -d '{}'
    ```
*   **What Success Looks Like**:
    1.  The curl request returns a `502 Bad Gateway` status.
    2.  `docker compose logs service-a` prints an `ERROR` log indicating `failed_to_reach_b`.
    3.  Service A remains running (it did not crash).
    4.  Restarting Service B (`docker compose start service-b`) restores successful loop routing.
*   **What to check if it fails**: Check the try/except block in Service A's `/request` route handler in `service-a/app.py`.

---

## 6. Common Problems and How to Fix Them

### Problem: Docker build fails
*   **Why**: Often a syntax error in a `Dockerfile` or missing files in the context.
*   **Fix**: Read the error output in your terminal. Ensure the context folder contains the required files (e.g., `requirements.txt` is in the folder where you run `docker compose`).

### Problem: Containers won't start
*   **Why**: A port conflict on your host machine. For example, if you run another local service, port 8080 is occupied.
*   **Fix**: Stop the local service running on port 8080, or modify Nginx's port mapping in `docker-compose.yml` to `9090:80` (you will then access Nginx at `http://localhost:9090`).

### Problem: Health checks fail
*   **Why**: The service is taking longer to start than the test timeout, or `curl` is missing inside the container image, or the container application is binding to the wrong IP.
*   **Fix**: Ensure `curl` is installed inside the image (via `apt-get` or `apk`). Check that the Flask app binds to `0.0.0.0` (all interfaces) rather than `127.0.0.1` inside the container.

### Problem: Service cannot reach another service
*   **Why**: Hardcoded `localhost` or `127.0.0.1` URLs inside application code.
*   **Fix**: Change the service endpoints in your application code (or compose environment variables) to use their Docker Compose service names (e.g., `http://service-b:3002` instead of `http://127.0.0.1:3002`).

### Problem: Nginx returns 502 Bad Gateway
*   **Why**: Service A is down, is booting up, or is bound to a different port than what Nginx expects.
*   **Fix**: Check if Service A is running using `docker compose ps` and read its logs to verify it started correctly on port 3001.

### Problem: Logs do not appear
*   **Why**: Python buffers console outputs by default.
*   **Fix**: Ensure `ENV PYTHONUNBUFFERED=1` is defined in each service `Dockerfile` or `PYTHONUNBUFFERED=1` is in the compose `environment` configuration.
