from fastapi import FastAPI, Request, Header
from fastapi.responses import JSONResponse
import os
import uvicorn
import requests
import uuid
import time
import threading
from datetime import datetime, timezone
from logger import get_logger

app = FastAPI()
logger = get_logger("service-c")
START_TIME = time.time()

BIND_HOST = os.environ.get("BIND_HOST", "127.0.0.1")
PORT = int(os.environ.get("PORT", "3003"))
SERVICE_A_URL = os.environ.get("SERVICE_A_URL", "http://service-a:3001")

def send_callback(request_id: str):
    """Fire-and-forget callback to Service A."""
    try:
        requests.post(
            f"{SERVICE_A_URL}/greeting-rcvd",
            headers={"X-Request-ID": request_id},
            json={
                "request_id": request_id,
                "source_service": "service-c",
                "message": "Greeting processed",
                "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            },
            timeout=5
        ).raise_for_status()
        logger.info("callback_sent", extra={
            "service_name": "service-c",
            "request_id": request_id,
            "path": "/greet-c",
            "status": 200,
            "method": "GET",
            "target": "service-a"
        })
    except requests.exceptions.RequestException as e:
        logger.error("callback_failed", extra={
            "service_name": "service-c",
            "request_id": request_id,
            "path": "/greet-c",
            "status": 502,
            "method": "GET",
            "error": str(e),
            "target": "service-a"
        })

@app.get("/health")
async def health(request: Request):
    request_id = str(uuid.uuid4())
    uptime = round(time.time() - START_TIME, 2)
    logger.info("health_check", extra={
        "service_name": "service-c",
        "request_id": request_id,
        "path": "/health",
        "status": 200,
        "method": "GET"
    })
    return {
        "service": "service-c",
        "status": "healthy",
        "port": 3003,
        "uptime_seconds": uptime,
        "check_type": "liveness"
    }

@app.get("/ready")
async def ready(request: Request):
    request_id = str(uuid.uuid4())
    logger.info("readiness_check", extra={
        "service_name": "service-c",
        "request_id": request_id,
        "path": "/ready",
        "status": 200,
        "method": "GET"
    })
    return {
        "service": "service-c",
        "status": "ready",
        "downstream": "none",
        "downstream_status": "n/a"
    }

@app.get("/greet-c")
def greet_c(request: Request, x_request_id: str = Header(None)):
    request_id = x_request_id or str(uuid.uuid4())
    logger.info("request_received", extra={
        "service_name": "service-c",
        "request_id": request_id,
        "path": "/greet-c",
        "status": 200,
        "method": "GET"
    })

    # Fire callback in background thread so we return immediately to Service B
    threading.Thread(target=send_callback, args=(request_id,), daemon=True).start()

    return {"request_id": request_id, "status": "processed", "callback_sent": True}

@app.get("/{path:path}")
async def catch_all(request: Request, path: str):
    request_id = str(uuid.uuid4())
    logger.info("route_not_found", extra={
        "service_name": "service-c",
        "request_id": request_id,
        "path": f"/{path}",
        "status": 404,
        "method": request.method
    })
    return JSONResponse(status_code=404, content={"error": "Not found"})

if __name__ == "__main__":
    uvicorn.run(app, host=BIND_HOST, port=PORT)
