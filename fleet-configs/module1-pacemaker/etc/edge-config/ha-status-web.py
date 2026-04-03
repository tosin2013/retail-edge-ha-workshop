#!/usr/bin/env python3
"""
Pacemaker HA Cluster Status Dashboard
Deployed via Fleet Manager to /etc/edge-config/ha-status-web.py

Serves an auto-refreshing HTML dashboard on port 8080 showing:
  - Pacemaker/Corosync/PCSD service status
  - PCS cluster overview and resources
  - STONITH fencing status
  - GFS2 shared storage mount and health
  - Peer connectivity
  - Fleet Manager agent status

Usage: python3 /etc/edge-config/ha-status-web.py
  Then: curl http://<vm-ip>:8080
"""

import subprocess
import socket
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

PORT = 8080


def run_cmd(cmd, timeout=10):
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
    peer_hostname = "rhel-ha-node2" if hostname == "rhel-ha-node1" else "rhel-ha-node1"

    checks = []

    # Services
    for svc in ["pacemaker", "corosync", "pcsd"]:
        active = check_service(svc)
        checks.append({
            "group": "Cluster Services",
            "name": svc.capitalize(),
            "status": "ok" if active else "fail",
            "detail": "Active" if active else "Inactive",
        })

    # PCS status
    pcs_out, pcs_rc = run_cmd("pcs status 2>&1", timeout=15)
    if pcs_rc == 0:
        checks.append({
            "group": "Cluster Overview",
            "name": "PCS Status",
            "status": "ok",
            "detail": pcs_out,
            "pre": True,
        })
    else:
        checks.append({
            "group": "Cluster Overview",
            "name": "PCS Status",
            "status": "warn",
            "detail": pcs_out or "Cluster not yet formed",
            "pre": True,
        })

    # Resources
    res_out, res_rc = run_cmd("pcs status resources 2>&1")
    checks.append({
        "group": "Resources",
        "name": "Cluster Resources",
        "status": "ok" if res_rc == 0 and res_out else "warn",
        "detail": res_out or "No resources configured",
        "pre": True,
    })

    # STONITH
    stonith_out, stonith_rc = run_cmd("pcs stonith status 2>&1")
    checks.append({
        "group": "Fencing",
        "name": "STONITH",
        "status": "ok" if stonith_rc == 0 and "Started" in stonith_out else "warn",
        "detail": stonith_out or "No fencing configured",
        "pre": True,
    })

    # GFS2 / Shared Storage
    mount_out, _ = run_cmd("mount | grep gfs2")
    vdb_exists, _ = run_cmd("test -b /dev/vdb && echo yes || echo no")

    if mount_out:
        mount_point = mount_out.split()[2] if len(mount_out.split()) > 2 else "/mnt/shared"
        df_out, _ = run_cmd(f"df -h {mount_point} | tail -1")
        write_test, wrc = run_cmd(
            f"touch {mount_point}/.status-test 2>/dev/null && rm -f {mount_point}/.status-test && echo ok"
        )
        checks.append({
            "group": "Shared Storage (GFS2)",
            "name": "GFS2 Mount",
            "status": "ok",
            "detail": f"Mounted at {mount_point}\n{df_out}",
            "pre": True,
        })
        checks.append({
            "group": "Shared Storage (GFS2)",
            "name": "Write Test",
            "status": "ok" if write_test == "ok" else "fail",
            "detail": "Read/write OK" if write_test == "ok" else "Cannot write to shared storage",
        })
    elif "yes" in vdb_exists:
        checks.append({
            "group": "Shared Storage (GFS2)",
            "name": "GFS2 Mount",
            "status": "warn",
            "detail": "Shared disk (/dev/vdb) attached but not yet mounted — complete Step 11",
        })
    else:
        checks.append({
            "group": "Shared Storage (GFS2)",
            "name": "GFS2 Mount",
            "status": "warn",
            "detail": "No shared disk attached yet — see Step 11",
        })

    for pkg in ["gfs2-utils", "dlm", "lvm2-lockd"]:
        _, rc = run_cmd(f"rpm -q {pkg}")
        checks.append({
            "group": "Shared Storage (GFS2)",
            "name": f"Package: {pkg}",
            "status": "ok" if rc == 0 else "warn",
            "detail": "Installed" if rc == 0 else "Not installed",
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
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "module": "Module 1: Pacemaker HA Cluster",
        "checks": checks,
    }


HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="15">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pacemaker HA Status</title>
<style>
  :root {
    --bg: #0f1117; --surface: #1a1d27; --border: #2a2d3a;
    --text: #e0e0e0; --muted: #888; --accent: #5b8def;
    --ok: #22c55e; --warn: #f59e0b; --fail: #ef4444;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: 'Segoe UI', system-ui, sans-serif; background: var(--bg); color: var(--text); padding: 24px; }
  .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; padding-bottom: 16px; border-bottom: 1px solid var(--border); }
  .header h1 { font-size: 1.4rem; color: var(--accent); }
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
    <h1>PACEMAKER_TITLE</h1>
    <div class="meta">PACEMAKER_HOST<br>PACEMAKER_TIME</div>
  </div>
  PACEMAKER_BODY
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
            badge = f'<span class="badge {item["status"]}">{item["status"]}</span>'
            detail = item["detail"]
            if item.get("pre"):
                detail = f'<pre class="detail">{detail}</pre>'
            else:
                detail = f'<div class="check-detail">{detail}</div>'
            body += f'<div class="check">{badge}<div><div class="check-name">{item["name"]}</div>{detail}</div></div>'
        body += "</div>"

    html = HTML_TEMPLATE
    html = html.replace("PACEMAKER_TITLE", data["module"])
    html = html.replace("PACEMAKER_HOST", f'{data["hostname"]} ({data["ip"]})')
    html = html.replace("PACEMAKER_TIME", data["timestamp"])
    html = html.replace("PACEMAKER_BODY", body)
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
        pass  # suppress request logs


if __name__ == "__main__":
    print(f"Pacemaker HA Status Dashboard listening on port {PORT}")
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
