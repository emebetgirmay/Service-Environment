from flask import Flask, request, jsonify
import requests
import json
import uuid
from datetime import datetime

app = Flask(__name__)

def log(level, event, trace_id, **kwargs):
    entry = {
        "timestamp": datetime.utcnow().isoformat(),
        "service": "service-c",
        "level": level,
        "event": event,
        "trace_id": trace_id,
        **kwargs
    }
    print(json.dumps(entry), flush=True)

@app.route("/health")
def health():
    return jsonify({"service": "service-c", "status": "ok"})

@app.route("/execute", methods=["POST"])
def execute():
    trace_id = request.headers.get("X-Trace-ID", str(uuid.uuid4()))
    log("INFO", "request_received", trace_id, path="/execute")
    try:
        resp = requests.post(
            "http://service-a.internal:3001/callback",
            json={"result": "done", "processed_by": "service-c"},
            headers={"X-Trace-ID": trace_id}
        )
        log("INFO", "callback_sent_to_a", trace_id, status=resp.status_code)
        return jsonify({"status": "executed"})
    except Exception as e:
        log("ERROR", "failed_to_callback_a", trace_id, error=str(e))
        return jsonify({"error": "callback failed"}), 502

@app.errorhandler(404)
def not_found(e):
    trace_id = request.headers.get("X-Trace-ID", "unknown")
    log("WARN", "invalid_route", trace_id, path=request.path)
    return jsonify({"error": "not found"}), 404

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=3003)
