from flask import Flask, request, jsonify
import requests
import json
import uuid
import os
from datetime import datetime

app = Flask(__name__)

SERVICE_B_URL = os.environ.get("SERVICE_B_URL", "http://service-b:3002/process")

def log(level, event, trace_id, **kwargs):
    entry = {
        "timestamp": datetime.utcnow().isoformat(),
        "service": "service-a",
        "level": level,
        "event": event,
        "trace_id": trace_id,
        **kwargs
    }
    print(json.dumps(entry), flush=True)

@app.route("/health")
def health():
    return jsonify({"service": "service-a", "status": "ok"})

@app.route("/request", methods=["POST"])
def handle_request():
    trace_id = request.headers.get("X-Request-ID") or request.headers.get("X-Trace-ID") or str(uuid.uuid4())
    log("INFO", "request_received", trace_id, path="/request")
    try:
        resp = requests.post(
            SERVICE_B_URL,
            json=request.get_json(),
            headers={
                "X-Request-ID": trace_id,
                "X-Trace-ID": trace_id
            }
        )
        log("INFO", "forwarded_to_b", trace_id, status=resp.status_code)
        return jsonify({"status": "accepted", "trace_id": trace_id})
    except Exception as e:
        log("ERROR", "failed_to_reach_b", trace_id, error=str(e))
        return jsonify({"error": "service-b unavailable"}), 502

@app.route("/callback", methods=["POST"])
def callback():
    data = request.get_json()
    trace_id = request.headers.get("X-Request-ID") or request.headers.get("X-Trace-ID") or "unknown"
    log("INFO", "callback_received", trace_id, data=data)
    return jsonify({"status": "callback_acknowledged"})

@app.errorhandler(404)
def not_found(e):
    trace_id = request.headers.get("X-Request-ID") or request.headers.get("X-Trace-ID") or "unknown"
    log("WARN", "invalid_route", trace_id, path=request.path)
    return jsonify({"error": "not found"}), 404

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3001)
