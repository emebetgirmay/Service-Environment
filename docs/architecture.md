# Architecture

## Service Architecture

Three Flask services behind an Nginx gateway, orchestrated with Docker Compose
on a single bridge network. Only Nginx publishes a host port (`8080:80`);
service-a/b/c (`3001`/`3002`/`3003`) are reachable only inside the Compose
network, confirmed by direct-connect tests returning `Connection refused`
from the host.

```
    Client
      │
      ▼
+-----------+
|   Nginx   |  (Public, :8080) — normalizes X-Request-ID / X-Trace-ID
+-----------+
      │ proxy_pass service-a:3001
      ▼
+-----------+
| Service A |  (:3001) — gateway coordinator
+-----------+
      │ POST /process
      ▼
+-----------+
| Service B |  (:3002) — internal processor
+-----------+
      │ POST /execute
      ▼
+-----------+
| Service C |  (:3003) — internal processor
+-----------+
      │ POST /callback (webhook back to A)
      ▼
+-----------------------+
| Service A (/callback) |
+-----------------------+
      │
      ▼
  Response → Client

  Observability side-channel (every service, on every request):
  Service A/B/C ──/metrics──► Prometheus ──► Grafana (dashboards + alert state)
  Service A/B/C ──OTLP/gRPC:4317──► Jaeger (:16686 UI)
```

## Request Flow

1. Client → Nginx (`:8080`). Nginx reads or generates `X-Request-ID`/`X-Trace-ID`
   and forwards both headers unchanged to service-a.
2. Nginx → Service A (`POST /request`). Service A logs `request_received`,
   then calls Service B (`SERVICE_B_URL`, default `http://service-b:3002/process`).
3. Service A → Service B (`POST /process`). Service B logs `request_received`,
   then calls Service C (`http://service-c:3003/execute`).
4. Service B → Service C (`POST /execute`). Service C logs `request_received`,
   then posts a callback to Service A (`http://service-a:3001/callback`).
5. Service C → Service A (`POST /callback`). Service A logs `callback_received`,
   completing the loop.
6. Response returns up the chain to the client, carrying a trace identifier
   in the JSON body and `X-Request-ID` in the response header. **Note:**
   since OpenTelemetry instrumentation landed, service-a's `/request`
   response now returns the `traceparent` header value (or the literal
   string `"otel-propagated"` if that header isn't present) in the
   `trace_id` field, rather than the manually-generated UUID from before —
   see `service-a/app.py`. The `X-Request-ID`/`X-Trace-ID` headers used for
   log correlation are still generated/forwarded independently of OTel, so
   log-based and trace-based correlation currently use two different IDs
   for the same request (see Known Limitations).

Any hop that fails to reach its downstream service catches the exception,
logs an `ERROR`-level event (`failed_to_reach_b`, `failed_to_reach_c`,
`failed_to_callback_a`), and returns `502` with a JSON error body rather
than crashing — this is what lets the stack degrade visibly instead of
failing silently.

**Live-validated:** stopping `service-b` (`docker compose stop service-b`)
and sending 30 sequential `POST /request` calls produced 30/30 `502
Bad Gateway` responses, each with a matching `failed_to_reach_b` ERROR log
in service-a carrying its own `trace_id` (full run in
`docs/benchmark-report.md`, Scenario 3). This confirms the degrade-gracefully
behavior described above is real, not just theoretical.

## Telemetry Flow

### Metrics Collection Flow — implemented (Joy)
Each service registers its own `CollectorRegistry` via
`shared/observability.py` (`register_observability(app, service_name)`) and
exposes `GET /metrics` in Prometheus exposition format. Four series are
collected:
- `http_requests_total{service, method, route, status_code}` (Counter)
- `http_request_duration_seconds{service, method, route, status_code}` (Histogram)
- `http_errors_total{service, method, route, status_code}` (Counter, incremented when `status_code >= 400`)
- `service_up{service}` (Gauge, set to `1` at process start)

Timing is captured via Flask `before_request`/`after_request` hooks, keyed
off `request.url_rule.rule` so metrics group by route pattern (e.g.
`/request`) rather than by literal path. `/metrics` itself is excluded from
its own timing to avoid self-measurement noise.

Prometheus (`prometheus.yml`) scrapes each service by Compose service name —
`service-a:3001`, `service-b:3002`, `service-c:3003` — with `job_name`
matching the service name, which is what `alert-rules.yml`'s
`up{job="service-a"}`-style conditions rely on. Scrape/evaluation interval
is 15s. Alert rule file (`alert-rules.yml`) is loaded via
`rule_files: /etc/prometheus/alert-rules.yml`.

Grafana connects to Prometheus as a datasource (`grafana/provisioning/datasources/prometheus.yml`,
`http://prometheus:9090`) and ships one provisioned dashboard
(`grafana/dashboards/service-overview.json`) with four panels: service
availability (`up{job=~"service-a|service-b|service-c"}`), request rate,
error rate, and p95 latency — all split out per service.

### Tracing Flow — implemented (Rita)
`shared/tracing.py` initializes an OpenTelemetry `TracerProvider` per
service (`init_tracer(service_name)`), exporting spans via OTLP/gRPC to
Jaeger's collector endpoint (`jaeger:4317`, overridable via
`OTEL_EXPORTER_OTLP_ENDPOINT`), batched through a `BatchSpanProcessor`.
Two auto-instrumentors are applied:
- `FlaskInstrumentor` (via `instrument_app(app)`) — creates a span for every
  incoming request to each service.
- `RequestsInstrumentor` — auto-instruments outbound `requests.post()` calls
  (A→B, B→C, C→A callback) and injects W3C `traceparent` headers, so spans
  across services link into one connected trace per request.

Jaeger's all-in-one container (`jaegertracing/all-in-one:1.57`) exposes the
OTLP gRPC/HTTP receivers (`4317`/`4318`) internally and the query UI on
`:16686` for viewing traces.

### Logging Flow (implemented today)
- Every service logs structured JSON to stdout via a shared `log()`
  helper (`shared/logger.py` / inline equivalents in each `app.py`).
- `trace_id` is read from `X-Request-ID` / `X-Trace-ID` on the incoming
  request, or generated with `uuid4()` if absent, and threaded through
  every log line and every outbound call's headers for that request.
- Nginx's own access log (`nginx.conf` `log_format main`) also includes
  `trace_id`, sourced from the same header via an nginx `map` block, so
  the gateway's access log line correlates with the three services' logs
  for the same request.
- Log access today: `docker compose logs [service-name]`, optionally
  `| grep <trace_id>` to pull one request's full cross-service story
  (see `docs/Container_VALIDATION.md` for a worked example).
- Loki/Promtail (optional, for viewing logs inside Grafana) — not yet added.

### Alerting Flow
Prometheus alert rules (`alert-rules.yml`) evaluate against the metrics
each service's `/metrics` endpoint exposes:
- **ServiceDown** — `up{job=~"service-a|service-b|service-c"} == 0`
- **HighErrorRate** — error/request ratio > 10% over 2m
- **HighLatency** — p95 request duration > 500ms over 5m

Each rule documents its meaning, likely causes, a manual reproduction
step, first checks, and how to confirm return to normal state (full detail
in `alert-rules.yml`). Alertmanager/Grafana notification routing is not
yet configured — current minimum is Prometheus-evaluated rules with
manual verification via `docker compose logs` and the Prometheus UI.

## Events

Documented operational moments for this stack (per PRD §4.5), represented
as structured log events and README/benchmark notes:
1. `request_received` / `request_completed` / error events
   (`failed_to_reach_b`, `failed_to_reach_c`, `failed_to_callback_a`) —
   logged per-request by every service, now including `duration_ms` on
   every completed request via the shared `before_request`/`after_request`
   timer.
2. Load test start/end — marked by k6's own stdout summary + timestamped
   entries in `docs/benchmark-report.md`.
3. Controlled failure triggered — three real mechanisms now exist:
   `GET /fail` (500, logged as `failure_endpoint_triggered`), `GET /slow`
   (1s delay, logged as `slow_endpoint_triggered`), or
   `docker compose stop service-b` (dependency-down, logged as
   `failed_to_reach_b`). All three are wired into `scripts/load-test.js`
   via the `FAILURE_TYPE` env var.

## Known Limitations

- **`trace_id` in the `/request` response body is not reliable.**
  `service-a/app.py`'s `/request` route returns
  `request.headers.get("traceparent", "otel-propagated")` — it reads the
  `traceparent` header off the *incoming* request from the client/nginx,
  not the outgoing OTel span it just created. Since neither curl nor k6
  sends a `traceparent` header, this field will almost always be the
  literal string `"otel-propagated"` rather than a real trace ID. The
  actual trace ID exists (visible in Jaeger's UI), just not surfaced back
  to the caller yet — worth flagging to Rita as a follow-up.
- **Two separate correlation IDs exist for the same request.** Structured
  logs correlate via `X-Request-ID`/`X-Trace-ID` (manually generated
  UUIDs, unchanged since before OTel was added). Jaeger correlates via its
  own OTel-generated trace ID (propagated through the auto-instrumented
  `traceparent` header on outbound `requests` calls). These two IDs are
  **not the same value** for a given request — so a log line's `trace_id`
  currently cannot be used to look up the matching trace in Jaeger's UI
  without a shared field connecting them. A follow-up would be logging the
  OTel trace ID (`trace.get_current_span().get_span_context().trace_id`)
  alongside the existing `request_id` in `shared/logger.py`.
- **Prometheus and Grafana container definitions weren't confirmed in the
  latest `docker-compose.yml` pull** — the version reviewed while writing
  this doc showed `prometheus-data`/`grafana-data` named volumes declared
  but only `nginx`, `service-a/b/c`, and `jaeger` service blocks were
  visible. If `docker compose ps` doesn't show `prometheus` and `grafana`
  containers running, those service definitions may be missing or were
  cut off in review — worth double-checking with Joy.
- No Alertmanager/notification channel configured — alerts are
  Prometheus-rule-only with manual verification via the Prometheus UI
  (Status → Alerts) and `docker compose logs`.
- `docs/benchmark-report.md`'s existing numbers predate `/fail` and
  `/slow` — its failure scenario still reflects the old
  `docker compose stop service-b` run. Re-run
  `k6 run -e SCENARIO=failure -e FAILURE_TYPE=fail scripts/load-test.js`
  (and again with `FAILURE_TYPE=slow`) to get real error-rate and latency
  numbers now that dedicated endpoints exist, and to confirm Prometheus
  alerts actually fire this time.