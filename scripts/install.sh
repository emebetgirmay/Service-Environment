#!/bin/bash
set -e

echo "========================================"
echo " Production Service Environment"
echo " Automated Installer"
echo "========================================"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USER_NAME="$(whoami)"

echo "[1/9] Updating package lists..."
sudo apt-get update -qq

echo "[2/9] Installing system dependencies..."
sudo apt-get install -y -qq python3 python3-pip python3-venv nginx

echo "[3/9] Setting up Python virtual environment..."
cd "$PROJECT_DIR"
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate
pip install -q -r requirements.txt

echo "[4/9] Configuring service discovery (/etc/hosts)..."
if ! grep -q "service-a.internal" /etc/hosts 2>/dev/null; then
    echo "127.0.0.1 service-a.internal" | sudo tee -a /etc/hosts > /dev/null
    echo "127.0.0.1 service-b.internal" | sudo tee -a /etc/hosts > /dev/null
    echo "127.0.0.1 service-c.internal" | sudo tee -a /etc/hosts > /dev/null
    echo "  Added service discovery entries to /etc/hosts"
else
    echo "  Service discovery entries already exist"
fi

if [ -f "/etc/cloud/templates/hosts.debian.tmpl" ]; then
    if ! grep -q "service-a.internal" /etc/cloud/templates/hosts.debian.tmpl 2>/dev/null; then
        echo "127.0.0.1 service-a.internal" | sudo tee -a /etc/cloud/templates/hosts.debian.tmpl > /dev/null
        echo "127.0.0.1 service-b.internal" | sudo tee -a /etc/cloud/templates/hosts.debian.tmpl > /dev/null
        echo "127.0.0.1 service-c.internal" | sudo tee -a /etc/cloud/templates/hosts.debian.tmpl > /dev/null
        echo "  Added to cloud-init template for reboot persistence"
    fi
fi

echo "[5/9] Generating systemd service files with dynamic paths..."
python3 "$PROJECT_DIR/scripts/generate_systemd.py" "$USER_NAME" "$PROJECT_DIR"
echo "  Generated systemd files for user=$USER_NAME, dir=$PROJECT_DIR"

echo "[6/9] Installing systemd service files..."
sudo cp "$PROJECT_DIR/systemd/"*.service /etc/systemd/system/
sudo systemctl daemon-reload

echo "[7/9] Enabling services for auto-start on boot..."
sudo systemctl enable service-c.service service-b.service service-a.service nginx

echo "[8/9] Configuring Nginx..."
sudo cp "$PROJECT_DIR/nginx/production-env.conf" /etc/nginx/sites-available/
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/production-env.conf /etc/nginx/sites-enabled/
sudo nginx -t

echo "[9/9] Starting services..."
sudo systemctl restart nginx
sudo systemctl start service-c
sleep 2
sudo systemctl start service-b
sleep 2
sudo systemctl start service-a
sleep 2

echo ""
echo "========================================"
echo "  Installation Complete!"
echo "========================================"
echo ""
echo "Verify with:"
echo "  curl http://localhost/service-a/health"
echo "  curl http://localhost/service-a/greet-service-b"
echo ""
echo "Check status:"
echo "  sudo systemctl status service-a"
echo ""
echo "View logs:"
echo "  sudo journalctl -u service-a -f"
echo ""
echo "Stop all services:"
echo "  sudo systemctl stop service-a service-b service-c"
echo ""
