# Benchmark Report

**Test tool used:** k6 (load), curl (failure scenario)
**Test command (normal + stress):**
```bash
k6 run scripts/load-test.js
```
**Test command (failure):**
```bash
docker compose stop service-b
for i in {1..30}; do curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:8080/request -H "Content-Type: application/json" -d '{}'; done
docker compose start service-b
```
Run against the full stack (`docker compose up -d`) with nginx, service-a,
service-b, and service-c all healthy before starting.

---

## Scenario 1 & 2: Normal + Stress Traffic (combined run)

**Purpose:** Establish baseline behavior, then observe latency/error behavior under pressure.
**Config:** k6 ran normal traffic (10 constant VUs, 50s) immediately followed by
stress traffic (ramping 0→50 VUs over 10s, hold 50 VUs for 30s, ramp down 10s)
in a single invocation, so results below are combined across both scenarios
rather than split out individually.

| Metric | Result |
|---|---|
| Requests sent | 10,211 |
| Concurrency | 10 → 50 (ramping) |
| Avg latency | 18.71ms |
| p95 latency | 31.54ms |
| Error rate | 0% (0 / 10,211 failed) |
| Alert triggered | None — latency stayed well under the 500ms HighLatency threshold even at 50 VUs |

**Observed in Grafana/Prometheus:** Not yet available — Prometheus has no
`/metrics` endpoints to scrape yet (Joy's deliverable, pending).
**Observed in Jaeger:** Not yet available — tracing instrumentation pending (Rita's deliverable).
**Observed in logs:** Confirmed via `docker compose logs`, e.g. a full
`request_received` → `forwarded_to_b` → `forwarded_to_c` → `callback_sent_to_a`
→ `callback_received` → `forwarded_to_b` chain correlated by a single
`trace_id` (see `docs/Container_VALIDATION.md` for a worked example of this
correlation on the running stack).

**Takeaway:** The system handled 50 concurrent VUs with no measurable
degradation — p95 stayed at 31.54ms, essentially the same as the baseline.
At this concurrency level, stress traffic did not meaningfully stress the
stack. A future run with higher VU counts (100+) would be needed to find
the actual breaking point and validate the HighLatency alert threshold.

---

## Scenario 3: Failure Traffic

**Purpose:** Prove alerts, traces, and logs work during failure.
**Config:** `service-b` stopped via `docker compose stop service-b`, then 30
sequential `POST /request` calls sent through the gateway.

> `/fail` / `/slow` / `/dependency-fail` controlled-failure endpoints are not
> yet implemented in service-a/b/c, so this scenario used a real dependency-down
> failure (stopping service-b) instead, per the PRD's Failure A pattern
> ("Service Down").

| Metric | Result |
|---|---|
| Requests sent | 30 |
| Concurrency | 1 (sequential) |
| Avg latency | N/A |
| p95 latency | N/A |
| Error rate | **100%** (30 / 30 returned `502 Bad Gateway`) |
| Alert triggered | ServiceDown would fire on this condition once Prometheus is scraping (not yet wired up — see Known Limitations) |

**Observed in Grafana/Prometheus:** Not yet available — no `/metrics` endpoint
to confirm `up{job="service-b"} == 0` yet.
**Observed in Jaeger:** Not yet available — tracing instrumentation pending.
**Observed in logs:** Confirmed. Every one of the 30 requests produced a
matching `ERROR`-level `failed_to_reach_b` log line in service-a, each with
its own unique `trace_id`. Sample:
```json
{"timestamp": "2026-07-10T17:55:02.458262", "service": "service-a", "level": "ERROR", "event": "failed_to_reach_b", "trace_id": "25c921f967828cfdce664881d2db3f8c", "error": "HTTPConnectionPool(host='service-b', port=3002): Max retries exceeded with url: /process (Caused by NameResolutionError(\"HTTPConnection(host='service-b', port=3002): Failed to resolve 'service-b' ([Errno -3] Temporary failure in name resolution)\"))"}
```
Client response confirmed for each request: `502 Bad Gateway` with body
`{"error":"service-b unavailable"}`.

**Takeaway:** Service-a degrades gracefully under a real dependency failure —
it never crashed, logged every failure at ERROR level with full context and
a correlating trace_id, and returned a clean 502 rather than an unhandled
exception. This is exactly the "expected evidence" the PRD's Failure A
scenario calls for at the logging layer; the metrics/alerting/tracing layers
just aren't built yet to confirm the same event automatically.

---

## Metrics Observed (Summary)

Not yet available. No service currently exposes `/metrics`, so Prometheus has
no `http_requests_total`, `http_errors_total`, `http_request_duration_seconds`,
or `service_up` series to query. This section will be filled in once Joy's
instrumentation lands — the alert rules in `alert-rules.yml` are already
written against these expected metric names.

## Alerts Triggered (Summary)

| Alert | Fired? | When | How confirmed |
|---|---|---|---|
| ServiceDown | Not evaluated (no Prometheus scrape target yet) | — | Manually confirmed equivalent condition: `docker compose stop service-b` produced 100% request failure and `failed_to_reach_b` logs |
| HighErrorRate | Not evaluated (no metrics yet) | — | Same manual evidence as above |
| HighLatency | Not evaluated (no metrics yet); did not appear to be near threshold | — | k6 stress run kept p95 at 31.54ms, far under the 500ms threshold |

## Traces Observed (Summary)

Not available yet — Jaeger has no spans to show until OpenTelemetry
instrumentation and trace-context propagation are added (Rita's deliverable).
Cross-service request correlation is currently proven via shared `trace_id`
in structured logs only (see log excerpts above).

## Lessons Learned

- The stack is stable and fast under normal/moderate concurrency: 10,211
  requests at up to 50 VUs, 0% errors, p95 of ~31ms.
- The failure simulation (stopping a dependency) is a reliable, reproducible
  way to prove degrade-gracefully behavior even without dedicated `/fail`
  endpoints — every one of 30 requests failed cleanly and loudly in the logs.
- The biggest gap right now is observability depth, not application
  correctness: the app already behaves well under both load and failure, but
  none of that is visible in Prometheus/Grafana/Jaeger yet because `/metrics`
  and tracing instrumentation haven't landed. Structured logs are currently
  doing all the work that metrics/traces/alerts are supposed to do.
- Once `/metrics` exists, re-run this exact same load test and failure
  sequence and this report should be updated to show live alert firing and
  Prometheus target state, not just log evidence.
- 50 VUs wasn't enough to find a real breaking point — worth re-testing at
  higher concurrency to validate the HighLatency alert's 500ms threshold
  actually means something for this stack.