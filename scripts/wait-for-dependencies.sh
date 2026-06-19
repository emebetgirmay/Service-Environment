#!/usr/bin/env bash
set -uo pipefail

MAX_WAIT_SECONDS=60
POLL_INTERVAL_SECONDS=2

declare -A DEPENDENCIES=(
    [service-b]="http://127.0.0.1:3002/health"
    [service-c]="http://127.0.0.1:3003/health"
)

log() {
    echo "[wait-for-dependencies] $*"
}

log "Waiting for dependencies: ${!DEPENDENCIES[*]}"

elapsed=0
pending=("${!DEPENDENCIES[@]}")

while [[ ${#pending[@]} -gt 0 && $elapsed -lt $MAX_WAIT_SECONDS ]]; do
    still_pending=()
    for name in "${pending[@]}"; do
        url="${DEPENDENCIES[$name]}"
        if curl -sf -o /dev/null --max-time 2 "$url"; then
            log "OK   $name is healthy ($url)"
        else
            log "WAIT $name not ready yet ($url)"
            still_pending+=("$name")
        fi
    done
    pending=("${still_pending[@]}")

    if [[ ${#pending[@]} -gt 0 ]]; then
        sleep "$POLL_INTERVAL_SECONDS"
        elapsed=$((elapsed + POLL_INTERVAL_SECONDS))
    fi
done

if [[ ${#pending[@]} -gt 0 ]]; then
    log "TIMEOUT after ${MAX_WAIT_SECONDS}s - still unavailable: ${pending[*]}"
    exit 1
fi

log "All dependencies healthy - proceeding to start Service A"
exit 0