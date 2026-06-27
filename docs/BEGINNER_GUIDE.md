# Containerization Beginner Guide

Welcome! If you have never used Docker or containerized an application before, this guide is written just for you. We will walk through the concepts behind this assignment, explaining how containers work, why we use them, and what every file in this repository does.

---

## 1. What This Assignment is Asking Us to Do
In the previous setup, this multi-service environment was designed to run on a Virtual Machine (VM) like Ubuntu. The processes were managed by `systemd` (a system manager that starts and stops programs on Linux), and they talked to each other using local hostnames mapped in `/etc/hosts` to the local loopback address `127.0.0.1`.

This assignment asks us to **containerize** the entire setup. We must package each service (Service A, B, C, and Nginx) into its own lightweight container and coordinate them using **Docker Compose**. Crucially, we must do this while **preserving the exact production behavior** (request flow, logging schema, request tracing, and network security policies).

---

## 2. What Containerization Means
Containerization is the process of packaging an application together with all of its dependencies (libraries, system tools, and runtime configurations) into a single isolated unit called a **container**. 
No matter what computer you run this container on (Mac, Windows, or Linux), it behaves exactly the same way because it carries its own environment with it.

---

## 3. What Docker Is
**Docker** is the platform and software tool that builds and runs containers.
* An **Image** is a read-only blueprint (like a class or a template) containing the OS files, runtime libraries, and your application code.
* A **Container** is a running instance of that image (like an object instantiated from a class). It runs as an isolated process on your host computer.

---

## 4. What Docker Compose Is
**Docker Compose** is a tool used for defining and running multi-container Docker applications. Instead of running four separate `docker run` commands and manually setting up networking between them, you define your entire application stack in a single text file named `docker-compose.yml`. You can then launch and manage the entire environment with a single command: `docker compose up`.

---

## 5. Why We Are Converting a VM Deployment into Containers
Deploying applications inside VMs has several major drawbacks:
* **Configuration Drift**: If you install packages manually, different VMs (development, staging, production) can drift and behave differently.
* **Heavyweight**: Every VM runs a full operating system, consuming gigabytes of memory and taking minutes to boot.
* **Complex Dependency Management**: Different apps running on the same VM might require different versions of the same library (e.g., Python 3.8 vs. Python 3.12), leading to package conflicts.

By moving to Docker Compose containers:
* The environment is declared in code (`Dockerfile` and `docker-compose.yml`), eliminating configuration drift.
* Containers share the host computer's operating system kernel, making them start in seconds and use minimal CPU and memory.
* Each container is isolated, meaning its dependencies never conflict with other containers.

---

## 6. The Difference Between Virtual Machines and Containers

| Feature | Virtual Machines (VMs) | Containers (Docker) |
| :--- | :--- | :--- |
| **Architecture** | Runs a full guest OS on top of virtualized hardware via a hypervisor. | Shares the host operating system's kernel; runs as an isolated process. |
| **Size** | Gigabytes (GB) due to containing full OS kernels and system files. | Megabytes (MB) because they contain only application code and minimal libraries. |
| **Startup Time** | Minutes (must boot a whole operating system). | Seconds (just starts a process). |
| **Isolation** | Hardware-level isolation (extremely secure, but high overhead). | OS-level process isolation (very secure, extremely lightweight). |

---

## 7. Why Nginx is the Only Public Entry Point
In modern production web architectures, we place a **Reverse Proxy** (Nginx) in front of our services.
* **Single Point of Entry**: Clients only talk to Nginx on the standard port `80`. Nginx then forwards (proxies) requests to Service A internally.
* **Security**: If Service A, B, or C were directly exposed to the public internet, hackers could scan their ports and attack them directly. By hiding them behind Nginx, we minimize the attack surface.
* **Header Control**: Nginx handles generating or passing through unique request tracking headers before they reach our application services.

---

## 8. Why Services B and C Must Remain Internal
Service B and Service C contain core business processing logic that is triggered only as downstream steps.
* Service B should only be called by Service A.
* Service C should only be called by Service B.
* Service C calls back to Service A.

If Service B or C were exposed to the host machine, an external user could bypass the validation, authentication, and logging implemented in Service A and invoke processing directly. Keeping them internal to the Docker network prevents this.

---

## 9. What Docker Networking Is
When Docker runs containers, it creates a private virtual network (by default, a **Bridge Network**) on your host computer.
* Containers attached to the same virtual network can talk to each other.
* They can resolve each other's IP addresses using their service names as hostnames.
* Docker provides an embedded DNS server at `127.0.0.11` inside the containers to handle this.
* Any container not attached to this network cannot reach them, providing strong security isolation.

---

## 10. Why We Use Service Names Instead of Localhost
On a virtual machine, all services ran on the same host, so they could talk to each other using `localhost` (or `127.0.0.1`) on different ports.
In Docker, **each container is its own virtual host**.
* Inside the Service A container, `localhost` refers to Service A itself, NOT the host computer or Service B.
* If Service A tries to call `http://localhost:3002`, it will fail because port 3002 is not listening inside Service A's container.
* Instead, we use Docker Compose service names (`service-b`, `service-c`, `service-a`). Docker's built-in DNS translates `http://service-b:3002` to the correct internal IP address of the Service B container.

---

## 11. What a Dockerfile Is
A `Dockerfile` is a text document containing all the commands a user could call on the command line to assemble an image.
Let's look at `service-a/Dockerfile` line-by-line:
1. `FROM python:3.12-slim`: Sets the base image to a lightweight, official Python environment.
2. `RUN apt-get update && apt-get install -y --no-install-recommends curl ...`: Installs the `curl` utility (needed to run container healthchecks).
3. `WORKDIR /app`: Creates and sets the active directory inside the image to `/app`.
4. `COPY requirements.txt .`: Copies the dependency file into the image.
5. `RUN pip install --no-cache-dir -r requirements.txt`: Installs Flask and Requests libraries.
6. `COPY service-a/ /app/service-a/`: Copies the Service A source code.
7. `EXPOSE 3001`: Informs Docker that the container listens on port 3001 at runtime.
8. `ENV PYTHONUNBUFFERED=1`: Ensures logs are written immediately (see Section 17).
9. `CMD ["python", "service-a/app.py"]`: Specifies the command to run when the container starts.

---

## 12. What docker-compose.yml Does
The `docker-compose.yml` file defines the services, networks, and volumes for your application.
Key configurations in our `docker-compose.yml`:
* `build`: Specifies where the `Dockerfile` is located.
* `depends_on`: Declares startup dependencies. Service A won't start until Services B and C are healthy.
* `ports`: Maps a container's port to the host computer. Nginx maps `80:80` (host port 80 maps to container port 80).
* `environment`: Sets environment variables inside the containers (like `SERVICE_B_URL` and `PYTHONUNBUFFERED`).
* `networks`: Attaches containers to our custom `production-net` network.

---

## 13. What .dockerignore Does
When Docker builds an image, it copies files from your host computer into the build context. The `.dockerignore` file prevents large or sensitive files (like local virtual environments `venv/`, git history `.git/`, temporary files, and logs) from being copied. This makes builds significantly faster and keeps container images small.

---

## 14. What Restart Policies Do
In `docker-compose.yml`, we use `restart: unless-stopped`.
This policy tells Docker to automatically restart a container if it crashes (exits with an error) or if the Docker daemon restarts (like when the host computer reboots). It will keep restarting the container indefinitely, *unless* the operator explicitly runs `docker compose stop` or `docker compose down`. This is crucial for maintaining production availability.

---

## 15. What Request Tracing Is
Request tracing is a technique used to follow the lifecycle of a request as it flows through a distributed system. As a request travels from Nginx to Service A, B, C, and back, we pass a unique identifier along. By printing this identifier in every log line, we can piece together the complete path of a request across different services.

---

## 16. Why X-Request-ID is Important
`X-Request-ID` is the standard HTTP header used for request tracing.
* If a request fails, you can search for the specific request ID across all container logs to pinpoint exactly which hop failed.
* The system also supports `X-Trace-ID` for backward compatibility with the older VM version of the project.

---

## 17. Why Logging to stdout/stderr Matters
In traditional VM deployments, apps write logs to files (e.g., `/var/log/app.log`). In containers, **writing logs to files is an anti-pattern**.
* Containers are ephemeral (they can be destroyed and recreated at any time). If you write logs inside a container's filesystem, they will be deleted when the container stops.
* Instead, we write all logs to the standard output (`stdout`) and standard error (`stderr`) streams using `print(..., flush=True)`.
* Docker automatically captures these streams and makes them accessible via `docker compose logs`.
* Setting `PYTHONUNBUFFERED=1` tells Python to disable internal output buffering, ensuring logs appear in your console *immediately* instead of waiting for a buffer to fill.

---

## 18. What Each Validation Test Is Checking

1. **Service Health Checks**:
   * *Command*: `curl http://localhost:8080/health` (routed through Nginx to Service A).
   * *Why*: Verifies Nginx reverse proxying is working and Service A is reachable.

2. **End-to-End Request Flow & Log Correlation**:
   * *Command*: `curl -X POST http://localhost:8080/request -H "Content-Type: application/json" -d '{"data": "test"}'`
   * *Why*: Triggers the entire Client → Nginx → A → B → C → A Callback loop. We then check `docker compose logs` to verify that all services log events (`request_received`, `forwarded_to_b`, etc.) containing the identical trace ID.

3. **Network Isolation**:
   * *Command*: `curl http://localhost:3002/health` and `curl http://localhost:3003/health` from the host.
   * *Why*: Verifies these calls fail. It ensures internal services are isolated from the host machine and are only accessible inside the private Docker network.

4. **Service Interruption Resilience**:
   * *Command*: `docker compose stop service-b` followed by an external curl request.
   * *Why*: Verifies that Service A degrades gracefully, logging `failed_to_reach_b` and returning a `502 Bad Gateway` status instead of crashing.

---

## 19. How to Debug the System If Something Fails
If something goes wrong:
1. Run `docker compose ps` to see which containers are running and if any have exited.
2. Read the logs of a failing container: `docker compose logs service-a`.
3. Check Nginx configuration errors: `docker compose logs nginx`.
4. Validate environment variable URLs inside the compose file.
5. If changes are made to application files, rebuild using `docker compose up --build -d`.

---

## 20. Glossary of Terms

* **Docker**: The platform used to build, share, and run containerized applications.
* **Container**: A running, isolated instance of a Docker image.
* **Image**: A read-only template containing the OS, libraries, and application code used to create containers.
* **Dockerfile**: A text file containing instructions to build a Docker image.
* **Compose**: A tool for defining and running multi-container Docker applications.
* **Network**: A virtual network created by Docker allowing containers to communicate securely.
* **Volume**: A mechanism for persisting data generated by and used by Docker containers.
* **Port**: A virtual endpoint for network communications (e.g., port 80 for HTTP).
* **Bind**: Configuring a socket or server to listen on a specific network interface/IP and port.
* **Reverse Proxy**: A proxy server that routes client requests to backend servers.
* **Nginx**: A popular open-source high-performance reverse proxy and web server.
* **Request ID**: A unique string assigned to an HTTP request to track it across services.
* **Callback**: An HTTP request sent by a backend service to report completion of a job.
* **Environment Variable**: A dynamic value set outside the application that configures its behavior at runtime.
* **Build**: The process of translating a Dockerfile into a runnable Docker image.
* **Runtime**: The environment in which an application executes (e.g., VM vs. Docker Compose).
