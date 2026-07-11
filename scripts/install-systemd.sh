#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/service-environment}"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

echo "==> Install path: $INSTALL_DIR"

echo "==> [1/5] Creating dedicated service users..."
for svc in svc-a svc-b svc-c; do
    if id "$svc" >/dev/null 2>&1; then
        echo "    User $svc already exists, skipping."
    else
        useradd --system --no-create-home --shell /usr/sbin/nologin "$svc"
        echo "    Created system user: $svc"
    fi
done

echo "==> [2/5] Placing application at $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp -r "$REPO_DIR"/service-a "$INSTALL_DIR"/
cp -r "$REPO_DIR"/service-b "$INSTALL_DIR"/
cp -r "$REPO_DIR"/service-c "$INSTALL_DIR"/
cp -r "$REPO_DIR"/scripts "$INSTALL_DIR"/

if [[ -d "$REPO_DIR/venv" ]]; then
    cp -r "$REPO_DIR/venv" "$INSTALL_DIR"/
else
    python3 -m venv "$INSTALL_DIR/venv"
    "$INSTALL_DIR/venv/bin/pip" install --quiet flask requests
fi

echo "==> [3/5] Setting ownership..."
for svc in a b c; do
    chown -R "svc-$svc:svc-$svc" "$INSTALL_DIR/service-$svc"
done
chown -R root:root "$INSTALL_DIR/venv" "$INSTALL_DIR/scripts"
chmod -R o+rx "$INSTALL_DIR/venv"
chmod o+rx "$INSTALL_DIR/scripts/wait-for-dependencies.sh"

echo "==> [4/5] Rendering and installing systemd unit files..."
for svc in a b c; do
    sed "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
        "$REPO_DIR/service-$svc/service-$svc.service" \
        > "/etc/systemd/system/service-$svc.service"
done

systemctl daemon-reload
systemctl enable service-a.service service-b.service service-c.service

poll_health() {
    local port="$1"
    local name="$2"
    local max_attempts=15
    local attempt=1
    echo "    Polling health for $name on port $port..."
    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "http://127.0.0.1:$port/health" >/dev/null; then
            echo "    OK   $name is healthy on port $port (attempt $attempt)"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    echo "    FAIL $name did not respond on port $port after $max_attempts seconds"
    return 1
}

echo "==> [5/5] Starting services in dependency order..."
echo "Starting service-c..."
systemctl start service-c.service
poll_health 3003 service-c || exit 1

echo "Starting service-b..."
systemctl start service-b.service
poll_health 3002 service-b || exit 1

echo "Starting service-a..."
systemctl start service-a.service
poll_health 3001 service-a || exit 1

echo "==> Verification complete!"