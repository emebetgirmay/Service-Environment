// scripts/load-test.js
//
// k6 load test for the Service-Environment stack.
//
// Run ALL THREE scenarios back to back (original behavior):
//   k6 run scripts/load-test.js
//
// Run ONE scenario only (no code edits needed — pass -e SCENARIO=...):
//   k6 run -e SCENARIO=normal  scripts/load-test.js
//   k6 run -e SCENARIO=stress  scripts/load-test.js
//   k6 run -e SCENARIO=failure scripts/load-test.js
//
// Targets the gateway (Nginx on :8080), which proxies EVERYTHING to
// service-a (see nginx.conf — single upstream). service-a then calls
// service-b -> service-c -> callback to service-a.
//
// FAILURE SCENARIO: `/fail` and `/slow` now exist on every service
// (service-a/b/c) as of Rita's app.py update. Through the gateway, only
// service-a's /fail and /slow are directly reachable (nginx only proxies to
// service-a). Pick which failure mode to exercise with FAILURE_TYPE:
//   - "fail" (default) -> GET/POST {BASE_URL}/fail   -> Failure C (High Error Rate), 500s
//   - "slow"            -> GET/POST {BASE_URL}/slow   -> Failure B (High Latency), +1s delay
//   - "down"            -> normal /request traffic; pair this run with
//                           `docker compose stop service-b` in another
//                           terminal to exercise Failure A (Service Down),
//                           since stopping a container isn't something k6
//                           itself can do.
//
// Examples:
//   k6 run -e SCENARIO=failure -e FAILURE_TYPE=fail scripts/load-test.js
//   k6 run -e SCENARIO=failure -e FAILURE_TYPE=slow scripts/load-test.js
//   docker compose stop service-b   # separate terminal
//   k6 run -e SCENARIO=failure -e FAILURE_TYPE=down scripts/load-test.js
//   docker compose start service-b  # restore after

import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend } from "k6/metrics";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";
const FAILURE_TYPE = (__ENV.FAILURE_TYPE || "fail").toLowerCase(); // fail | slow | down

// Which scenario(s) to run this invocation. "all" (default) runs all three
// back to back, in sequence, matching the original single-run behavior.
const SCENARIO = (__ENV.SCENARIO || "all").toLowerCase();

const errorRate = new Rate("custom_error_rate");
const requestDuration = new Trend("custom_request_duration");

const ALL_SCENARIOS = {
  normal_traffic: {
    executor: "constant-vus",
    vus: 10,
    duration: "50s", // ~500 requests at 10 VUs, ~1 req/s each
    exec: "normalTraffic",
  },
  stress_traffic: {
    executor: "ramping-vus",
    startVUs: 0,
    stages: [
      { duration: "10s", target: 50 },
      { duration: "30s", target: 50 },
      { duration: "10s", target: 0 },
    ],
    exec: "stressTraffic",
  },
  failure_traffic: {
    executor: "constant-vus",
    vus: 10,
    duration: "30s",
    exec: "failureTraffic",
  },
};

// Map the SCENARIO env var to which scenario keys to include, and build
// startTime offsets automatically so multi-scenario runs still execute in
// sequence (only relevant when SCENARIO=all).
function buildScenarios() {
  const order =
    SCENARIO === "all"
      ? ["normal_traffic", "stress_traffic", "failure_traffic"]
      : SCENARIO === "normal"
      ? ["normal_traffic"]
      : SCENARIO === "stress"
      ? ["stress_traffic"]
      : SCENARIO === "failure"
      ? ["failure_traffic"]
      : (() => {
          throw new Error(
            `Unknown SCENARIO "${SCENARIO}". Use all | normal | stress | failure.`
          );
        })();

  const scenarios = {};
  let offsetSeconds = 0;
  const durationSeconds = { normal_traffic: 50, stress_traffic: 50, failure_traffic: 30 };

  for (const key of order) {
    scenarios[key] = {
      ...ALL_SCENARIOS[key],
      startTime: `${offsetSeconds}s`,
    };
    offsetSeconds += durationSeconds[key] + 5; // small gap between scenarios
  }
  return scenarios;
}

export const options = {
  scenarios: buildScenarios(),
  thresholds: {
    http_req_duration: ["p(95)<2000"], // generous ceiling; real target is 500ms per alert rule
  },
};

function postRequest() {
  const payload = JSON.stringify({ data: "load-test" });
  const params = { headers: { "Content-Type": "application/json" } };
  const res = http.post(`${BASE_URL}/request`, payload, params);

  const ok = check(res, {
    "status is 200": (r) => r.status === 200,
    "has trace_id": (r) => {
      try {
        return JSON.parse(r.body).trace_id !== undefined;
      } catch {
        return false;
      }
    },
  });

  errorRate.add(!ok);
  requestDuration.add(res.timings.duration);
  return res;
}

// Scenario 1: Normal traffic — establish baseline behavior.
export function normalTraffic() {
  postRequest();
  sleep(1);
}

// Scenario 2: Stress traffic — observe latency/error behavior under pressure.
export function stressTraffic() {
  postRequest();
  sleep(0.2);
}

// Scenario 3: Failure traffic — prove alerts/traces/logs work during failure.
//
// FAILURE_TYPE=fail  -> hits GET {BASE_URL}/fail, service-a returns 500
//                        every time (drives HighErrorRate).
// FAILURE_TYPE=slow  -> hits GET {BASE_URL}/slow, service-a sleeps 1s then
//                        returns 200 (drives HighLatency; p95 should jump
//                        to ~1000ms, well above the 500ms alert threshold).
// FAILURE_TYPE=down  -> sends normal /request traffic; pair this run with
//                        `docker compose stop service-b` in another
//                        terminal so service-a's calls to service-b fail
//                        (drives ServiceDown / HighErrorRate for service-b).
export function failureTraffic() {
  if (FAILURE_TYPE === "slow") {
    const res = http.get(`${BASE_URL}/slow`);
    check(res, { "slow endpoint returned 200": (r) => r.status === 200 });
    requestDuration.add(res.timings.duration);
  } else if (FAILURE_TYPE === "down") {
    postRequest();
  } else {
    // default: "fail"
    const res = http.get(`${BASE_URL}/fail`);
    const ok = check(res, { "fail endpoint returned 500": (r) => r.status === 500 });
    errorRate.add(!ok ? false : true); // expected failure counts as a successful failure-test, not a script error
    requestDuration.add(res.timings.duration);
  }
  sleep(0.5);
}