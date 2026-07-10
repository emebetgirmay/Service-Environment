"""
OpenTelemetry Tracing Setup Module
==================================
PURPOSE:
    Initializes OpenTelemetry tracing, sets up context propagation,
    and exports spans to the Jaeger collector over OTLP/gRPC.
"""

import os
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor

def init_tracer(service_name):
    """
    Initializes the global OpenTelemetry tracer provider, registers the OTLP
    span processor pointing to Jaeger, and instruments HTTP outgoing requests.
    """
    # Jaeger container listens for OTLP gRPC on port 4317
    otlp_endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "jaeger:4317")
    
    # Configure resource properties (service name)
    resource = Resource.create({"service.name": service_name})
    
    # Create the Tracer Provider
    provider = TracerProvider(resource=resource)
    
    # Configure OTLP Span Exporter
    exporter = OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True)
    
    # Process spans in batches for performance
    processor = BatchSpanProcessor(exporter)
    provider.add_span_processor(processor)
    
    # Set the global tracer provider
    trace.set_tracer_provider(provider)
    
    # Automatically instrument outgoing requests (context propagation)
    # This automatically adds W3C traceparent headers to requests.get/post
    RequestsInstrumentor().instrument()
    
    return trace.get_tracer(service_name)

def instrument_app(app):
    """
    Instruments incoming requests for a Flask application.
    """
    FlaskInstrumentor().instrument_app(app)
