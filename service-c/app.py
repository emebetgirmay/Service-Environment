from flask import Flask, request, jsonify, g
import requests
import json
import uuid
import os
import time
from datetime import datetime, timezone
from shared.logger import create_logger
from shared.tracing import init_tracer, instrument_app
from shared.observability import register_observability

# Initialize OpenTelemetry Tracing
init_tracer("service-c")

app = Flask(__name__)

# Instrument Flask app for incoming traces
instrument_app(app)

# Register Prometheus metrics /metrics endpoint and metrics capture
register_observability(app, "service-c")

# Initialize custom structured logger
log = create_logger("service-c")

SERVICE_A_URL = os.environ.get("SERVICE_A_URL", "http://service-a:3001/callback")

@app.before_request
def start_timer():
    g.start_time = time.time()
    g.request_id = request.headers.get("X-Request-ID") or request.headers.get("X-Trace-ID") or str(uuid.uuid4())
    log("INFO", "request_received")

@app.after_request
def log_response(response):
    duration_ms = 0
    if hasattr(g, 'start_time'):
        duration_ms = int((time.time() - g.start_time) * 1000)
    
    log("INFO", "request_completed", 
        status=response.status_code, 
        duration_ms=duration_ms)
    return response

@app.route("/health")
def health():
    return jsonify({"service": "service-c", "status": "ok", "version": os.environ.get("APP_VERSION", "unknown")})

@app.route("/execute", methods=["POST"])
def execute():
    try:
        resp = requests.post(
            SERVICE_A_URL,
            json={"result": "done", "processed_by": "service-c"},
            headers={
                "X-Request-ID": g.request_id,
                "X-Trace-ID": g.request_id
            }
        )
        log("INFO", "callback_sent_to_a", status=resp.status_code)
        return jsonify({"status": "executed"})
    except Exception as e:
        log("ERROR", "failed_to_callback_a", error=str(e))
        return jsonify({"error": "callback failed"}), 502

# Lab-only Controlled Failure Endpoints for Observability validation
@app.route("/slow", methods=["GET", "POST"])
def slow():
    time.sleep(1.0)
    log("WARN", "slow_endpoint_triggered")
    return jsonify({"status": "delayed", "latency_ms": 1000})

@app.route("/fail", methods=["GET", "POST"])
def fail():
    log("ERROR", "failure_endpoint_triggered")
    return jsonify({"error": "simulated server failure"}), 500

@app.errorhandler(404)
def not_found(e):
    log("WARN", "invalid_route")
    return jsonify({"error": "not found"}), 404

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3003)
