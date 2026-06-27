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

    def log(level, event, **kwargs):
        """
        Write a structured JSON log entry to stdout.

        This function creates a dictionary (a collection of key-value pairs),
        converts it to JSON (a text format), and prints it as a single line.

        Args:
            level (str): How important is this log?
                         "INFO"  = normal operation
                         "WARN"  = something unusual happened
                         "ERROR" = something went wrong

            event (str): What happened? Must be one of:
                         "request_received"   - a new request arrived
                         "request_forwarded"  - request sent to next service
                         "callback_received"  - callback arrived from Service C
                         "request_failed"     - an error occurred
                         "route_not_found"    - someone hit a URL that doesn't exist

            **kwargs: Additional fields to include in the log.
                      Common ones:
                          request_id="abc-123"    - the tracking ID
                          path="/health"          - which URL was hit
                          status=200              - HTTP status code
                          method="GET"            - HTTP method
                          error="connection refused"  - error details
                          target="service-b"      - which service was called
        """

        # Build the log entry as a Python dictionary.
        # The assignment requires these specific fields:
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),  # When it happened
            "service": service_name,                               # Which service
            "level": level,                                        # Severity
            "event": event,                                        # What happened
        }

        # Add any extra fields passed by the caller (request_id, path, status, etc.)
        # The ** syntax means "unpack all keyword arguments into this dictionary"
        entry.update(kwargs)

        # Print as a single line of JSON to stdout.
        #
        # WHY flush=True?
        # Normally, Python waits until it has a bunch of text before actually
        # writing it out (called "buffering"). flush=True says "write it NOW."
        # This is important because systemd/journalctl reads stdout in real time,
        # and we don't want logs to be delayed or lost.
        print(json.dumps(entry), flush=True)

    return log
