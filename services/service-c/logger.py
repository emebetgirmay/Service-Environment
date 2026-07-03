import json
import logging
import sys
from datetime import datetime, timezone

class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_obj = {
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "service": getattr(record, "service_name", "unknown"),
            "event": record.msg,
            "request_id": getattr(record, "request_id", "none"),
            "path": getattr(record, "path", "unknown"),
            "status": getattr(record, "status", 0),
            "method": getattr(record, "method", "UNKNOWN"),
        }
        if hasattr(record, "target"):
            log_obj["target"] = record.target
        if hasattr(record, "source_service"):
            log_obj["source_service"] = record.source_service
        if hasattr(record, "error"):
            log_obj["error"] = record.error
        return json.dumps(log_obj)

def get_logger(service_name):
    logger = logging.getLogger(service_name)
    logger.setLevel(logging.INFO)
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(JSONFormatter())
        logger.addHandler(handler)
    logger.service_name = service_name
    return logger
