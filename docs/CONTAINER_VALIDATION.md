# Container Validation Evidence

## 1. Start the System

```bash
$ docker compose up --build -d
[+] Building 50.8s (27/27) FINISHED
 => [service-a] exporting to image
 => => naming to docker.io/library/production-service-environment-service-a:latest
 => [service-b] exporting to image
 => => naming to docker.io/library/production-service-environment-service-b:latest
 => [service-c] exporting to image
 => => naming to docker.io/library/production-service-environment-service-c:latest
[+] Running 5/5
 ✔ Network production-service-environment_app-network  Created
 ✔ Container service-c                                 Started
 ✔ Container service-a                                 Started
 ✔ Container service-b                                 Started
 ✔ Container nginx                                     Started
$ docker compose ps
NAME        IMAGE                                      COMMAND                  SERVICE     CREATED         STATUS         PORTS
nginx       nginx:alpine                               "/docker-entrypoint.…"   nginx       2 minutes ago   Up 2 minutes   0.0.0.0:8080->80/tcp, :::8080->80/tcp
service-a   production-service-environment-service-a   "python services/ser…"   service-a   2 minutes ago   Up 2 minutes   3001/tcp
service-b   production-service-environment-service-b   "python services/ser…"   service-b   2 minutes ago   Up 2 minutes   3002/tcp
service-c   production-service-environment-service-c   "python services/ser…"   service-c   2 minutes ago   Up 2 minutes   3003/tcp
$ curl -s http://localhost:8080/service-a/health | python3 -m json.tool
{
    "service": "service-a",
    "status": "healthy",
    "port": 3001,
    "uptime_seconds": 89.87,
    "check_type": "liveness"
}
$ curl -i --connect-timeout 3 http://localhost:3002/health
curl: (7) Failed to connect to localhost port 3002 after 0 ms: Couldnt connect to server

$ curl -i --connect-timeout 3 http://localhost:3003/health
curl: (7) Failed to connect to localhost port 3003 after 0 ms: Couldnt connect to server
$ docker compose exec service-a python -c "import urllib.request; print(urllib.request.urlopen('http://service-b:3002/health').read().decode())"
{"service":"service-b","status":"healthy","port":3002,"uptime_seconds":157.02,"check_type":"liveness"}

$ docker compose exec service-b python -c "import urllib.request; print(urllib.request.urlopen('http://service-c:3003/health').read().decode())"
{"service":"service-c","status":"healthy","port":3003,"uptime_seconds":167.46,"check_type":"liveness"}
$ curl -s http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: demo-container-001" | python3 -m json.tool
{
    "request_id": "demo-container-001",
    "status": "success",
    "message": "Request completed successfully"
}
$ docker compose logs | grep demo-container-001
service-b  | {"timestamp": "2026-06-25T13:07:19Z", "service": "service-b", "event": "request_received", "request_id": "demo-container-001", "path": "/greet", "status": 200, "method": "GET"}
service-b  | {"timestamp": "2026-06-25T13:07:19Z", "service": "service-b", "event": "request_forwarded", "request_id": "demo-container-001", "path": "/greet", "status": 200, "method": "GET", "target": "service-c"}
service-c  | {"timestamp": "2026-06-25T13:07:19Z", "service": "service-c", "event": "request_received", "request_id": "demo-container-001", "path": "/greet-c", "status": 200, "method": "GET"}
service-c  | {"timestamp": "2026-06-25T13:07:19Z", "service": "service-c", "event": "callback_sent", "request_id": "demo-container-001", "path": "/greet-c", "status": 200, "method": "GET", "target": "service-a"}
service-a  | {"timestamp": "2026-06-25T13:07:19Z", "service": "service-a", "event": "request_received", "request_id": "demo-container-001", "path": "/greet-service-b", "status": 200, "method": "GET"}
service-a  | {"timestamp": "2026-06-25T13:07:19Z", "service": "service-a", "event": "callback_received", "request_id": "demo-container-001", "path": "/greeting-rcvd", "status": 200, "method": "POST", "source_service": "service-c"}
service-a  | {"timestamp": "2026-06-25T13:07:19Z", "service": "service-a", "event": "request_completed", "request_id": "demo-container-001", "path": "/greet-service-b", "status": 200, "method": "GET"}
nginx      | {"timestamp":"2026-06-25T13:07:19+00:00","request_id":"demo-container-001","method":"GET","path":"/service-a/greet-service-b","status":200,"upstream":"172.18.0.3:3001","request_time":0.215}
$ docker compose stop service-b
[+] Stopping 1/1
 ✔ Container service-b  Stopped

$ curl -s http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: fail-service-b-001" | python3 -m json.tool
{
    "request_id": "fail-service-b-001",
    "status": "error",
    "message": "Service B unreachable"
}
$ docker compose logs service-a | grep fail-service-b-001
service-a  | {"timestamp": "2026-06-25T13:08:04Z", "service": "service-a", "event": "request_received", "request_id": "fail-service-b-001", "path": "/greet-service-b", "status": 200, "method": "GET"}
service-a  | {"timestamp": "2026-06-25T13:08:04Z", "service": "service-a", "event": "request_failed", "request_id": "fail-service-b-001", "path": "/greet-service-b", "status": 502, "method": "GET", "error": "service_b_unreachable"}
$ docker compose start service-b
[+] Running 1/1
 ✔ Container service-b  Started

$ curl -s http://localhost:8080/service-a/greet-service-b -H "X-Request-ID: recover-service-b-001" | python3 -m json.tool
{
    "request_id": "recover-service-b-001",
    "status": "success",
    "message": "Request completed successfully"
}
```
