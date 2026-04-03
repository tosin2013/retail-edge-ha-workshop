#!/usr/bin/env python3
"""
MicroShift VRRP Gateway Status Dashboard
Deployed via Fleet Manager to /etc/edge-config/gateway-status-web.py

Serves an auto-refreshing HTML dashboard on port 8080 showing:
  - MicroShift service and API health
  - Keepalived / VRRP state and VIP ownership
  - Pod and workload status
  - Firewall configuration
  - Peer connectivity
  - Fleet Manager agent status

Usage: python3 /etc/edge-config/gateway-status-web.py
  Then: curl http://<vm-ip>:8080
"""

import subprocess
import socket
import json
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

PORT = 8080
VIP = "10.102.0.100"
KUBECONFIG = "/home/cloud-user/.kube/config"


def run_cmd(cmd, timeout=10, env=None):
    try:
        merged = os.environ.copy()
        if env:
            merged.update(env)
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout, env=merged
        )
        return result.stdout.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "Command timed out", 1
    except Exception as e:
        return str(e), 1


def get_ip(iface="eth1"):
    out, _ = run_cmd(f"ip -4 addr show {iface} 2>/dev/null | grep -oP 'inet \\K[0-9.]+'")
    lines = out.split("\n") if out else []
    return lines[0] if lines else "N/A"


def check_service(name):
    _, rc = run_cmd(f"systemctl is-active --quiet {name}")
    return rc == 0


def oc_cmd(cmd):
    return run_cmd(cmd, env={"KUBECONFIG": KUBECONFIG})


def get_checks():
    hostname = socket.gethostname()
    my_ip = get_ip()
    peer_hostname = "microshift-gw-b" if hostname == "microshift-gw-a" else "microshift-gw-a"

    checks = []

    # MicroShift
    ms_active = check_service("microshift")
    checks.append({
        "group": "MicroShift",
        "name": "Service",
        "status": "ok" if ms_active else "fail",
        "detail": "Active" if ms_active else "Inactive",
    })

    api_out, api_rc = run_cmd("curl -k -s --max-time 3 https://localhost:6443/readyz")
    checks.append({
        "group": "MicroShift",
        "name": "API Server (6443)",
        "status": "ok" if api_rc == 0 else "fail",
        "detail": api_out or ("Healthy" if api_rc == 0 else "Not responding"),
    })

    # Pods
    if os.path.exists(KUBECONFIG):
        pods_out, pods_rc = oc_cmd("oc get pods -A --no-headers 2>&1")
        if pods_rc == 0 and pods_out:
            lines = pods_out.strip().split("\n")
            running = sum(1 for l in lines if "Running" in l)
            checks.append({
                "group": "MicroShift",
                "name": "Workloads",
                "status": "ok" if running > 0 else "warn",
                "detail": f"{running}/{len(lines)} pods running",
            })
            checks.append({
                "group": "MicroShift",
                "name": "Pod List",
                "status": "ok",
                "detail": pods_out,
                "pre": True,
            })
        else:
            checks.append({
                "group": "MicroShift",
                "name": "Workloads",
                "status": "warn",
                "detail": pods_out or "Cannot list pods",
            })

    # Keepalived / VRRP
    ka_active = check_service("keepalived")
    checks.append({
        "group": "Keepalived / VRRP",
        "name": "Service",
        "status": "ok" if ka_active else "fail",
        "detail": "Active" if ka_active else "Inactive",
    })

    has_vip, _ = run_cmd(f"ip -4 addr show eth1 2>/dev/null | grep -c {VIP}")
    is_master = has_vip.strip() != "0"
    checks.append({
        "group": "Keepalived / VRRP",
        "name": f"VIP ({VIP})",
        "status": "ok" if is_master else "warn",
        "detail": "MASTER — VIP is on this node" if is_master else "BACKUP — VIP is on peer",
    })

    vrrp_out, _ = run_cmd(
        "journalctl -u keepalived --no-pager -n 100 2>/dev/null"
        " | grep -oP '(Entering|entering) (MASTER|BACKUP|FAULT) STATE' | tail -1"
    )
    checks.append({
        "group": "Keepalived / VRRP",
        "name": "Last VRRP Transition",
        "status": "ok",
        "detail": vrrp_out or "No transitions recorded",
    })

    # Firewall
    fw_active = check_service("firewalld")
    checks.append({
        "group": "Firewall",
        "name": "firewalld",
        "status": "ok" if fw_active else "warn",
        "detail": "Active" if fw_active else "Not running",
    })
    if fw_active:
        protos, _ = run_cmd("firewall-cmd --list-protocols 2>/dev/null")
        checks.append({
            "group": "Firewall",
            "name": "VRRP Protocol",
            "status": "ok" if "vrrp" in (protos or "") else "fail",
            "detail": "Allowed" if "vrrp" in (protos or "") else "Not in firewall rules",
        })

    # Peer connectivity
    peer_ip_out, _ = run_cmd(f"getent hosts {peer_hostname} 2>/dev/null | awk '{{print $1}}'")
    if peer_ip_out:
        _, ping_rc = run_cmd(f"ping -c 1 -W 2 {peer_ip_out}")
        checks.append({
            "group": "Peer Connectivity",
            "name": f"{peer_hostname} ({peer_ip_out})",
            "status": "ok" if ping_rc == 0 else "fail",
            "detail": "Reachable" if ping_rc == 0 else "Unreachable",
        })
    else:
        checks.append({
            "group": "Peer Connectivity",
            "name": peer_hostname,
            "status": "warn",
            "detail": "Not in /etc/hosts — peer discovery pending",
        })

    _, vip_ping = run_cmd(f"ping -c 1 -W 2 {VIP}")
    checks.append({
        "group": "Peer Connectivity",
        "name": f"VIP ({VIP})",
        "status": "ok" if vip_ping == 0 else "warn",
        "detail": "Reachable" if vip_ping == 0 else "Unreachable",
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
        "vip_master": is_master,
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "module": "Module 2: MicroShift VRRP Gateway",
        "checks": checks,
    }


HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="10">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MicroShift Gateway Status</title>
<style>
  :root {
    --bg: #0f1117; --surface: #1a1d27; --border: #2a2d3a;
    --text: #e0e0e0; --muted: #888; --accent: #a78bfa;
    --ok: #22c55e; --warn: #f59e0b; --fail: #ef4444;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: 'Segoe UI', system-ui, sans-serif; background: var(--bg); color: var(--text); padding: 24px; }
  .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; padding-bottom: 16px; border-bottom: 1px solid var(--border); }
  .header h1 { font-size: 1.4rem; color: var(--accent); }
  .vip-badge { display: inline-block; padding: 4px 12px; border-radius: 12px; font-size: 0.8rem; font-weight: 700; margin-left: 12px; }
  .vip-master { background: rgba(34,197,94,0.2); color: var(--ok); }
  .vip-backup { background: rgba(245,158,11,0.2); color: var(--warn); }
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
  <div class="footer">Auto-refreshes every 10s &middot; <a href="/api" style="color:var(--accent)">JSON API</a></div>
</body>
</html>"""


def render_html(data):
    groups = {}
    for c in data["checks"]:
        groups.setdefault(c["group"], []).append(c)

    vip_label = "MASTER" if data.get("vip_master") else "BACKUP"
    vip_cls = "vip-master" if data.get("vip_master") else "vip-backup"

    body = ""
    for group_name, items in groups.items():
        body += f'<div class="group"><div class="group-title">{group_name}</div>'
        for item in items:
            badge = f'<span class="badge {item["status"]}">{item["status"]}</span>'
            detail = item["detail"]
            if item.get("pre"):
                detail = f'<pre class="detail">{detail}</pre>'
            else:
                detail = f'<div class="check-detail">{detail}</div>'
            body += f'<div class="check">{badge}<div><div class="check-name">{item["name"]}</div>{detail}</div></div>'
        body += "</div>"

    html = HTML_TEMPLATE
    title = f'{data["module"]} <span class="vip-badge {vip_cls}">{vip_label}</span>'
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
    print(f"MicroShift Gateway Status Dashboard listening on port {PORT}")
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
