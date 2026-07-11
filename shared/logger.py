"""
Shared Structured Logger Module
================================

PURPOSE:
    This module provides ONE consistent logging function used by ALL services
    (A, B, and C). Instead of each service having its own copy of the log()
    function, they all import this one.

WHAT IT DOES:
    - Creates structured JSON log entries
    - Prints them to stdout (the terminal)
    - Ensures every log has the fields required by the assignment:
      timestamp, service, event, request_id, path, status

HOW TO USE:
    from shared.logger import create_logger

    log = create_logger("service-a")
    log("INFO", "request_received", request_id="abc-123", path="/health")

ASSIGNMENT REQUIREMENTS SATISFIED:
    - Structured JSON logging
    - Consistent log format across all services
    - Required fields: timestamp, service, event, request_id, path, status
    - Logs answer: What happened? When? Which service? Which request? Outcome?
"""

import json
from datetime import datetime, timezone


def create_logger(service_name):
    """
    Creates a logging function for a specific service.

    HOW IT WORKS:
        You call create_logger("service-a") and it gives you back a function.
        That function already knows it belongs to "service-a" — you don't have
        to tell it every time.

    BEGINNER ANALOGY:
        It's like getting a personalized stamp at work. The stamp already has
        your department name on it. When you stamp a form, your department
        is automatically included.

    Args:
        service_name (str): The name of the service, e.g., "service-a",
                            "service-b", or "service-c".

    Returns:
        function: A log function that outputs structured JSON to stdout.
    """

    from opentelemetry import trace
    from flask import g, request, has_app_context

    def log(level, event, **kwargs):
        # Get active OpenTelemetry trace ID and span ID
        current_span = trace.get_current_span()
        trace_id = "unknown"
        span_id = "unknown"
        if current_span and current_span.get_span_context().is_valid:
            trace_id = format(current_span.get_span_context().trace_id, '032x')
            span_id = format(current_span.get_span_context().span_id, '16x')

        # Build log entry with standard required fields
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "service": service_name,
            "level": level,
            "event": event,
            "trace_id": trace_id,
            "span_id": span_id,
        }

        # Try to resolve Flask request context
        if has_app_context():
            # Auto-resolve request_id
            if hasattr(g, "request_id") and g.request_id:
                entry["request_id"] = g.request_id
            elif request.headers.get("X-Request-ID"):
                entry["request_id"] = request.headers.get("X-Request-ID")
            
            # If method and path are not in kwargs, auto-resolve them
            if "method" not in kwargs:
                entry["method"] = request.method
            if "path" not in kwargs:
                entry["path"] = request.path

        # Add any extra fields passed by the caller (overriding auto-detected ones if needed)
        entry.update(kwargs)

        print(json.dumps(entry), flush=True)

    return log
