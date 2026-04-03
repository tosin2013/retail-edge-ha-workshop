#!/usr/bin/env python3
"""
Two-Node OpenShift Cluster Status Dashboard
Deployed via Fleet Manager to /etc/edge-config/cluster-status-web.py

Serves an auto-refreshing HTML dashboard on port 8080 showing:
  - Node role and hostname
  - Network connectivity matrix (master1 <-> master2 <-> arbiter)
  - Simulated etcd quorum status
  - Disk performance baseline (dsync latency)
  - Fleet Manager agent status

Usage: python3 /etc/edge-config/cluster-status-web.py
  Then: curl http://<vm-ip>:8080
"""

import subprocess
import socket
import json
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

PORT = 8080

ALL_NODES = {
    "master1": "twonode-master1",
    "master2": "twonode-master2",
    "arbiter": "twonode-arbiter",
}


def run_cmd(cmd, timeout=15):
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        return result.stdout.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "Command timed out", 1
    except Exception as e:
        return str(e), 1


def get_ip(iface="eth1"):
    out, _ = run_cmd(f"ip -4 addr show {iface} 2>/dev/null | grep -oP 'inet \\K[0-9.]+'")
    return out.split("\n")[0] if out else "N/A"


def check_service(name):
    _, rc = run_cmd(f"systemctl is-active --quiet {name}")
    return rc == 0


def get_checks():
    hostname = socket.gethostname()
    my_ip = get_ip()

    role_file = "/etc/edge-config/device-role"
    role = "unknown"
    if os.path.exists(role_file):
        with open(role_file) as f:
            role = f.read().strip()

    checks = []

    # Node Identity
    checks.append({
        "group": "Node Identity",
        "name": "Hostname",
        "status": "ok",
        "detail": hostname,
    })
    checks.append({
        "group": "Node Identity",
        "name": "Role",
        "status": "ok",
        "detail": role,
    })
    checks.append({
        "group": "Node Identity",
        "name": "IP (eth1)",
        "status": "ok" if my_ip != "N/A" else "fail",
        "detail": my_ip,
    })

    # Network Connectivity Matrix
    for node_role, node_hostname in ALL_NODES.items():
        if node_hostname == hostname:
            continue
        ip_out, _ = run_cmd(f"getent hosts {node_hostname} 2>/dev/null | awk '{{print $1}}'")
        if ip_out:
            _, ping_rc = run_cmd(f"ping -c 1 -W 2 {ip_out}")
            checks.append({
                "group": "Network Connectivity",
                "name": f"{node_hostname} ({ip_out})",
                "status": "ok" if ping_rc == 0 else "fail",
                "detail": "Reachable" if ping_rc == 0 else "Unreachable",
            })
        else:
            checks.append({
                "group": "Network Connectivity",
                "name": node_hostname,
                "status": "warn",
                "detail": "Not in /etc/hosts — peer discovery pending",
            })

    # etcd Quorum (simulated)
    total_nodes = 3
    reachable = sum(
        1 for c in checks
        if c["group"] == "Network Connectivity" and c["status"] == "ok"
    ) + 1  # include self

    quorum_needed = (total_nodes // 2) + 1
    has_quorum = reachable >= quorum_needed

    checks.append({
        "group": "etcd Quorum (Simulated)",
        "name": "Members Reachable",
        "status": "ok" if has_quorum else "fail",
        "detail": f"{reachable}/{total_nodes} nodes reachable (quorum requires {quorum_needed})",
    })
    checks.append({
        "group": "etcd Quorum (Simulated)",
        "name": "Quorum Status",
        "status": "ok" if has_quorum else "fail",
        "detail": "Quorum maintained" if has_quorum else "QUORUM LOST — cluster cannot accept writes",
    })

    if role in ("master1", "master2"):
        checks.append({
            "group": "etcd Quorum (Simulated)",
            "name": "etcd Role",
            "status": "ok",
            "detail": "Voting member (data + leader election)",
        })
    elif role == "arbiter":
        checks.append({
            "group": "etcd Quorum (Simulated)",
            "name": "etcd Role",
            "status": "ok",
            "detail": "Arbiter (voting only — no data storage)",
        })

    # Disk Performance
    dd_out, dd_rc = run_cmd(
        "dd if=/dev/zero of=/var/tmp/test-etcd bs=512 count=1000 oflag=dsync 2>&1 | tail -1"
    )
    run_cmd("rm -f /var/tmp/test-etcd")
    if dd_rc == 0 and dd_out:
        checks.append({
            "group": "Disk Performance",
            "name": "dsync Write (512B x 1000)",
            "status": "ok",
            "detail": dd_out,
        })
    else:
        checks.append({
            "group": "Disk Performance",
            "name": "dsync Write",
            "status": "warn",
            "detail": dd_out or "Could not run disk test",
        })

    # Fleet Manager
    agent_active = check_service("flightctl-agent")
    checks.append({
        "group": "Fleet Manager",
        "name": "flightctl-agent",
        "status": "ok" if agent_active else "warn",
        "detail": "Running" if agent_active else "Not running",
    })

    return {
        "hostname": hostname,
        "ip": my_ip,
        "role": role,
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "module": "Module 3: Two-Node OpenShift with Arbiter",
        "checks": checks,
    }


HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="15">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Two-Node OCP Status</title>
<style>
  :root {
    --bg: #0f1117; --surface: #1a1d27; --border: #2a2d3a;
    --text: #e0e0e0; --muted: #888; --accent: #f97316;
    --ok: #22c55e; --warn: #f59e0b; --fail: #ef4444;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: 'Segoe UI', system-ui, sans-serif; background: var(--bg); color: var(--text); padding: 24px; }
  .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; padding-bottom: 16px; border-bottom: 1px solid var(--border); }
  .header h1 { font-size: 1.4rem; color: var(--accent); }
  .role-badge { display: inline-block; padding: 4px 12px; border-radius: 12px; font-size: 0.8rem; font-weight: 700; margin-left: 12px; background: rgba(249,115,22,0.2); color: var(--accent); }
  .meta { font-size: 0.85rem; color: var(--muted); text-align: right; }
  .group { margin-bottom: 20px; }
  .group-title { font-size: 0.9rem; font-weight: 600; color: var(--accent); margin-bottom: 8px; text-transform: uppercase; letter-spacing: 0.05em; }
  .check { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 12px 16px; margin-bottom: 6px; display: flex; align-items: flex-start; gap: 12px; }
  .badge { display: inline-block; padding: 2px 10px; border-radius: 12px; font-size: 0.75rem; font-weight: 600; text-transform: uppercase; flex-shrink: 0; margin-top: 2px; }
  .badge.ok { background: rgba(34,197,94,0.15); color: var(--ok); }
  .badge.warn { background: rgba(245,158,11,0.15); color: var(--warn); }
  .badge.fail { background: rgba(239,68,68,0.15); color: var(--fail); }
  .check-name { font-weight: 600; font-size: 0.9rem; }
  .check-detail { font-size: 0.85rem; color: var(--muted); margin-top: 2px; }
  pre.detail { background: #12141c; padding: 10px; border-radius: 6px; font-size: 0.8rem; overflow-x: auto; white-space: pre-wrap; margin-top: 6px; color: var(--text); max-height: 300px; overflow-y: auto; }
  .footer { margin-top: 24px; padding-top: 12px; border-top: 1px solid var(--border); font-size: 0.8rem; color: var(--muted); text-align: center; }
</style>
</head>
<body>
  <div class="header">
    <div><h1>STATUS_TITLE</h1></div>
    <div class="meta">STATUS_HOST<br>STATUS_TIME</div>
  </div>
  STATUS_BODY
  <div class="footer">Auto-refreshes every 15s &middot; <a href="/api" style="color:var(--accent)">JSON API</a></div>
</body>
</html>"""


def render_html(data):
    groups = {}
    for c in data["checks"]:
        groups.setdefault(c["group"], []).append(c)

    body = ""
    for group_name, items in groups.items():
        body += f'<div class="group"><div class="group-title">{group_name}</div>'
        for item in items:
            badge_html = f'<span class="badge {item["status"]}">{item["status"]}</span>'
            detail = item["detail"]
            if item.get("pre"):
                detail = f'<pre class="detail">{detail}</pre>'
            else:
                detail = f'<div class="check-detail">{detail}</div>'
            body += f'<div class="check">{badge_html}<div><div class="check-name">{item["name"]}</div>{detail}</div></div>'
        body += "</div>"

    html = HTML_TEMPLATE
    role = data.get("role", "unknown")
    title = f'{data["module"]} <span class="role-badge">{role}</span>'
    html = html.replace("STATUS_TITLE", title)
    html = html.replace("STATUS_HOST", f'{data["hostname"]} ({data["ip"]})')
    html = html.replace("STATUS_TIME", data["timestamp"])
    html = html.replace("STATUS_BODY", body)
    return html


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        data = get_checks()
        if self.path == "/api":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(data, indent=2).encode())
        else:
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(render_html(data).encode())

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    print(f"Two-Node OCP Status Dashboard listening on port {PORT}")
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
