"""
Request Tracing & Logging Middleware
=====================================

PURPOSE:
    This middleware automatically handles X-Request-ID and logging for EVERY
    request — without you having to add logging code to each route function.

WHAT IS MIDDLEWARE?
    Middleware is code that runs automatically before and after your route
    functions. Think of it as a security guard at a building entrance:
    - When someone enters (before_request): the guard checks their badge,
      records their arrival, and gives them a visitor badge if they don't have one.
    - When someone leaves (after_request): the guard records their departure.
    You don't have to tell each person to check in — the guard does it
    automatically for everyone.

WHAT THIS MIDDLEWARE DOES:
    1. BEFORE each request:
       - Reads X-Request-ID from the incoming request header
       - If no X-Request-ID exists, generates a new unique one (UUID)
       - Stores it in Flask's 'g' object (a per-request storage container)
       - Records the start time (so we can calculate response time later)
       - Logs "request_received"

    2. AFTER each request:
       - Adds X-Request-ID to the response headers (so the client gets it back)

    3. ON 404 ERROR (page not found):
       - Logs "route_not_found" with the invalid path

    4. ON 500 ERROR (unexpected crash):
       - Logs "request_failed" with the error details

WHAT IS Flask's 'g' OBJECT?
    'g' is like a clipboard that exists only during one request. When a new
    request comes in, Flask gives you a fresh clipboard. You can write notes
    on it (like the request ID), and any code that runs during that request
    can read those notes. When the request is done, the clipboard is thrown away.

ASSIGNMENT REQUIREMENTS SATISFIED:
    - Every request must contain X-Request-ID
    - If missing, must be generated
    - Same request ID must propagate through all services
    - All 404s must generate structured logs (event: route_not_found)
    - All failures must be logged (event: request_failed)

HOW TO USE:
    from shared.middleware import register_middleware
    from shared.logger import create_logger

    app = Flask(__name__)
    log = create_logger("service-a")
    register_middleware(app, log)
"""

import uuid
import time
import traceback

from flask import request, g, jsonify


def register_middleware(app, log):
    """
    Register logging and tracing middleware on a Flask app.

    This function attaches automatic behavior to the Flask app:
    - Before every request: extract/generate X-Request-ID, log arrival
    - After every request: add X-Request-ID to response headers
    - On 404: log route_not_found
    - On 500: log request_failed

    Args:
        app: The Flask application instance (the thing created by Flask(__name__))
        log: A logging function from create_logger() (already configured with service name)
    """

    # ─────────────────────────────────────────────────────────────────
    # BEFORE REQUEST — runs BEFORE your route function
    # ─────────────────────────────────────────────────────────────────

    @app.before_request
    def before_request_handler():
        """
        Runs automatically before EVERY request reaches your route function.

        Step 1: Read X-Request-ID from the incoming request headers.
                If the header doesn't exist, generate a new unique ID (UUID).
                Store it in g.request_id so any code during this request can access it.

        Step 2: Record the current time so we can calculate how long the request takes.

        Step 3: Log "request_received" — the assignment requires this event.

        WHAT IS UUID?
            UUID stands for Universally Unique Identifier. It's a long random
            string like "550e8400-e29b-41d4-a716-446655440000". The chances of
            two UUIDs being identical are astronomically small — essentially
            impossible. This makes them perfect for tracking individual requests.
        """

        # Step 1: Get or generate the request ID
        # request.headers.get() tries to read the header.
        # If the header is missing, it uses the second argument as a fallback.
        g.request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))

        # Step 2: Record when the request started
        # time.time() returns the current time as a number (seconds since 1970).
        # We'll use this later to calculate how many milliseconds the request took.
        g.start_time = time.time()

        # Step 3: Log that we received a request
        log("INFO", "request_received",
            request_id=g.request_id,
            method=request.method,     # GET, POST, etc.
            path=request.path)         # /health, /greet-service-b, etc.

    # ─────────────────────────────────────────────────────────────────
    # AFTER REQUEST — runs AFTER your route function returns a response
    # ─────────────────────────────────────────────────────────────────

    @app.after_request
    def after_request_handler(response):
        """
        Runs automatically after EVERY request, just before the response is
        sent back to the client.

        What it does:
        - Adds X-Request-ID to the response headers so the client can see it.
          This is helpful for troubleshooting: the client can say "my request
          ID was abc-123, can you check the logs?"

        Args:
            response: The HTTP response object that Flask is about to send.

        Returns:
            The response object (with the added header).
        """

        # Add the request ID to the response headers.
        # getattr() safely reads g.request_id. If before_request didn't run
        # (which shouldn't happen, but just in case), it falls back to "unknown".
        response.headers["X-Request-ID"] = getattr(g, "request_id", "unknown")

        return response

    # ─────────────────────────────────────────────────────────────────
    # 404 ERROR HANDLER — runs when someone requests a URL that doesn't exist
    # ─────────────────────────────────────────────────────────────────

    @app.errorhandler(404)
    def handle_not_found(error):
        """
        Handles requests to URLs that don't exist.

        WHAT IS A 404?
            When someone requests a page that doesn't exist (like /xyz), the
            web server returns HTTP status code 404 — "Not Found." It's like
            going to an office building and asking for a department that
            doesn't exist.

        ASSIGNMENT REQUIREMENT:
            "Unknown routes must: 1. Return 404. 2. Generate structured logs."
            Event name must be "route_not_found".
        """

        log("WARN", "route_not_found",
            request_id=getattr(g, "request_id", "unknown"),
            method=request.method,
            path=request.path,
            status=404)

        return jsonify({"error": "not found"}), 404

    # ─────────────────────────────────────────────────────────────────
    # 500 ERROR HANDLER — catches unexpected crashes (unhandled exceptions)
    # ─────────────────────────────────────────────────────────────────

    @app.errorhandler(Exception)
    def handle_exception(error):
        """
        Catches ANY unhandled exception — things you didn't expect to go wrong.

        WHAT IS A 500 ERROR?
            When your code crashes unexpectedly (a bug, a missing variable,
            a database error), the web server returns HTTP status code 500 —
            "Internal Server Error." Without this handler, the error would
            show up as an ugly HTML page, and nothing would be logged.

        ASSIGNMENT REQUIREMENT:
            "All failures must be logged" including "unexpected exceptions."
            Event name must be "request_failed".

        WHAT IS traceback.format_exc()?
            When Python crashes, it shows you a stack trace — a list of
            every function that was running when the error happened, like
            a trail of breadcrumbs. traceback.format_exc() captures that
            trail as text so we can include it in the log.
        """

        log("ERROR", "request_failed",
            request_id=getattr(g, "request_id", "unknown"),
            method=request.method,
            path=request.path,
            status=500,
            error=str(error),
            traceback=traceback.format_exc())

        return jsonify({"error": "internal server error"}), 500
