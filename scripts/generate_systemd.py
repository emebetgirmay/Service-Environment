import sys
import os

def generate(user, project_dir):
    services = {
        "service-c": {
            "description": "Service C - Internal Processing Service",
            "after": "network.target",
            "wants": "",
            "app": "services/service-c/app.py"
        },
        "service-b": {
            "description": "Service B - Internal Forwarding Service",
            "after": "network.target service-c.service",
            "wants": "Wants=service-c.service",
            "app": "services/service-b/app.py"
        },
        "service-a": {
            "description": "Service A - Public API Gateway",
            "after": "network.target service-b.service service-c.service",
            "wants": "Wants=service-b.service service-c.service",
            "app": "services/service-a/app.py"
        }
    }

    for svc, cfg in services.items():
        wants_line = cfg["wants"] + "\n" if cfg["wants"] else ""
        content = f"""[Unit]
Description={cfg["description"]}
After={cfg["after"]}
{wants_line}[Service]
Type=simple
User={user}
WorkingDirectory={project_dir}
Environment=PATH={project_dir}/venv/bin
ExecStart={project_dir}/venv/bin/python3 {cfg["app"]}
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
"""
        with open(f"{project_dir}/systemd/{svc}.service", "w") as f:
            f.write(content)
        print(f"  Generated {svc}.service")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: generate_systemd.py <user> <project_dir>")
        sys.exit(1)
    generate(sys.argv[1], sys.argv[2])
