from flask import Flask, request, jsonify, g
import requests
import json
import uuid
import os
import time
from datetime import datetime, timezone
from shared.logger import create_logger
from shared.tracing import init_tracer, instrument_app

# Initialize OpenTelemetry Tracing
init_tracer("service-a")

app = Flask(__name__)
# Instrument Flask app for incoming traces
instrument_app(app)

log = create_logger("service-a")

SERVICE_B_URL = os.environ.get("SERVICE_B_URL", "http://service-b:3002/process")

@app.before_request
def start_timer():
    g.start_time = time.time()
    # Read trace_id or request_id if available to initialize request context
    g.request_id = request.headers.get("X-Request-ID") or request.headers.get("X-Trace-ID") or str(uuid.uuid4())
    log("INFO", "request_received")

@app.after_request
def log_response(response):
    duration_ms = 0
    if hasattr(g, 'start_time'):
        duration_ms = int((time.time() - g.start_time) * 1000)
    
    # Log the response metrics
    log("INFO", "request_completed", 
        status=response.status_code, 
        duration_ms=duration_ms)
    return response

@app.route("/health")
def health():
    return jsonify({"service": "service-a", "status": "ok"})

@app.route("/request", methods=["POST"])
def handle_request():
    try:
        # Outgoing requests.post is auto-instrumented by RequestsInstrumentor.
        # Traceparent context header is injected automatically.
        resp = requests.post(
            SERVICE_B_URL,
            json=request.get_json(),
            headers={
                "X-Request-ID": g.request_id,
                "X-Trace-ID": g.request_id
            }
        )
        log("INFO", "forwarded_to_b", status=resp.status_code)
        return jsonify({"status": "accepted", "trace_id": request.headers.get("traceparent", "otel-propagated")})
    except Exception as e:
        log("ERROR", "failed_to_reach_b", error=str(e))
        return jsonify({"error": "service-b unavailable"}), 502

@app.route("/callback", methods=["POST"])
def callback():
    data = request.get_json()
    log("INFO", "callback_received", data=data)
    return jsonify({"status": "callback_acknowledged"})

# Lab-only Controlled Failure Endpoints for Observability validation
@app.route("/slow", methods=["GET", "POST"])
def slow():
    time.sleep(1.0) # Introduce a latency of 1 second
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
    app.run(host="0.0.0.0", port=3001)
