"""Reusable Prometheus instrumentation for the Flask services."""

import time

from flask import Response, g, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)


def register_observability(app, service_name):
    """Expose /metrics and collect HTTP traffic, errors, latency and liveness."""
    registry = CollectorRegistry()
    labels = ("service", "method", "route", "status_code")
    requests_total = Counter("http_requests_total", "Total HTTP requests.", labels, registry=registry)
    request_duration = Histogram(
        "http_request_duration_seconds", "HTTP request duration in seconds.", labels, registry=registry
    )
    errors_total = Counter("http_errors_total", "Total HTTP 4xx and 5xx responses.", labels, registry=registry)
    service_up = Gauge("service_up", "Service process availability (1 = up).", ("service",), registry=registry)
    service_up.labels(service=service_name).set(1)

    @app.before_request
    def start_metrics_timer():
        if request.path != "/metrics":
            g.metrics_started_at = time.perf_counter()

    @app.after_request
    def record_http_metrics(response):
        started_at = getattr(g, "metrics_started_at", None)
        if started_at is None:
            return response
        route = request.url_rule.rule if request.url_rule else request.path
        metric_labels = {
            "service": service_name,
            "method": request.method,
            "route": route,
            "status_code": str(response.status_code),
        }
        requests_total.labels(**metric_labels).inc()
        request_duration.labels(**metric_labels).observe(time.perf_counter() - started_at)
        if response.status_code >= 400:
            errors_total.labels(**metric_labels).inc()
        return response

    @app.get("/metrics")
    def metrics():
        return Response(
            generate_latest(registry), mimetype=CONTENT_TYPE_LATEST
        )
