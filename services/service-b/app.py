from fastapi import FastAPI, Request, Header
from fastapi.responses import JSONResponse
import os
import uvicorn
import requests
import uuid
import time
from logger import get_logger

app = FastAPI()
logger = get_logger("service-b")
START_TIME = time.time()

BIND_HOST = os.environ.get("BIND_HOST", "127.0.0.1")
PORT = int(os.environ.get("PORT", "3002"))
SERVICE_C_URL = os.environ.get("SERVICE_C_URL", "http://service-c:3003")

@app.get("/health")
async def health(request: Request):
    request_id = str(uuid.uuid4())
    uptime = round(time.time() - START_TIME, 2)
    logger.info("health_check", extra={
        "service_name": "service-b",
        "request_id": request_id,
        "path": "/health",
        "status": 200,
        "method": "GET"
    })
    return {
        "service": "service-b",
        "status": "healthy",
        "port": 3002,
        "uptime_seconds": uptime,
        "check_type": "liveness"
    }

@app.get("/ready")
async def ready(request: Request):
    request_id = str(uuid.uuid4())
    try:
        resp = requests.get(
            f"{SERVICE_C_URL}/health",
            headers={"X-Request-ID": request_id},
            timeout=2
        )
        resp.raise_for_status()
        logger.info("readiness_check", extra={
            "service_name": "service-b",
            "request_id": request_id,
            "path": "/ready",
            "status": 200,
            "method": "GET",
            "target": "service-c"
        })
        return {
            "service": "service-b",
            "status": "ready",
            "downstream": "service-c",
            "downstream_status": "healthy"
        }
    except requests.exceptions.RequestException as e:
        logger.error("readiness_check_failed", extra={
            "service_name": "service-b",
            "request_id": request_id,
            "path": "/ready",
            "status": 503,
            "method": "GET",
            "error": str(e),
            "target": "service-c"
        })
        return JSONResponse(status_code=503, content={
            "service": "service-b",
            "status": "not_ready",
            "downstream": "service-c",
            "downstream_status": "unreachable"
        })

@app.get("/greet")
def greet(request: Request, x_request_id: str = Header(None)):
    request_id = x_request_id or str(uuid.uuid4())
    logger.info("request_received", extra={
        "service_name": "service-b",
        "request_id": request_id,
        "path": "/greet",
        "status": 200,
        "method": "GET"
    })
    try:
        requests.get(
            f"{SERVICE_C_URL}/greet-c",
            headers={"X-Request-ID": request_id},
            timeout=5
        ).raise_for_status()
    except requests.exceptions.RequestException:
        logger.error("request_failed", extra={
            "service_name": "service-b",
            "request_id": request_id,
            "path": "/greet",
            "status": 502,
            "method": "GET",
            "error": "service_c_unreachable"
        })
        return JSONResponse(status_code=502, content={
            "request_id": request_id,
            "status": "error",
            "target": "service-c"
        })

    logger.info("request_forwarded", extra={
        "service_name": "service-b",
        "request_id": request_id,
        "path": "/greet",
        "status": 200,
        "method": "GET",
        "target": "service-c"
    })
    return {"request_id": request_id, "status": "forwarded", "target": "service-c"}

@app.get("/{path:path}")
async def catch_all(request: Request, path: str):
    request_id = str(uuid.uuid4())
    logger.info("route_not_found", extra={
        "service_name": "service-b",
        "request_id": request_id,
        "path": f"/{path}",
        "status": 404,
        "method": request.method
    })
    return JSONResponse(status_code=404, content={"error": "Not found"})

if __name__ == "__main__":
    uvicorn.run(app, host=BIND_HOST, port=PORT)
