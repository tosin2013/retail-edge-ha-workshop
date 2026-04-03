#!/usr/bin/env python3
"""
Two-Node OpenShift Cluster Status Dashboard (runs as OpenShift pod)

Queries the OpenShift API for VM status and tests network connectivity
to VMI IPs. Does NOT run inside the VMs (RHCOS has no flightctl-agent).

Serves an auto-refreshing HTML dashboard on port 8080 showing:
  - VM running state (from OpenShift API)
  - Network connectivity matrix between VMs
  - Simulated etcd quorum status
  - Cluster resource usage

Requires a ServiceAccount with view access to the student namespace.
"""

import subprocess
import json
import os
import urllib.request
import ssl
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

PORT = 8080
NAMESPACE = os.environ.get("NAMESPACE", "retail-edge-student-01")
API_SERVER = "https://kubernetes.default.svc"
TOKEN_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/token"
CA_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

VM_NAMES = ["twonode-master1", "twonode-master2", "twonode-arbiter"]
VM_ROLES = {
    "twonode-master1": "Control Plane 1",
    "twonode-master2": "Control Plane 2",
    "twonode-arbiter": "etcd Arbiter",
}


def k8s_get(path):
    try:
        with open(TOKEN_PATH) as f:
            token = f.read().strip()
        ctx = ssl.create_default_context(cafile=CA_PATH)
        req = urllib.request.Request(
            f"{API_SERVER}{path}",
            headers={"Authorization": f"Bearer {token}"},
        )
        with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}


def run_cmd(cmd, timeout=5):
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        return result.stdout.strip(), result.returncode
    except Exception:
        return "", 1


def get_checks():
    checks = []

    vms = k8s_get(f"/apis/kubevirt.io/v1/namespaces/{NAMESPACE}/virtualmachines")
    vmis = k8s_get(f"/apis/kubevirt.io/v1/namespaces/{NAMESPACE}/virtualmachineinstances")

    vm_map = {}
    if "items" in vms:
        for vm in vms["items"]:
            name = vm["metadata"]["name"]
            if name in VM_NAMES:
                status = vm.get("status", {}).get("printableStatus", "Unknown")
                vm_map[name] = {"status": status}

    vmi_ips = {}
    if "items" in vmis:
        for vmi in vmis["items"]:
            name = vmi["metadata"]["name"]
            if name in VM_NAMES:
                phase = vmi.get("status", {}).get("phase", "Unknown")
                ifs = vmi.get("status", {}).get("interfaces", [])
                ips = [i.get("ipAddress", "") for i in ifs if i.get("ipAddress")]
                vmi_ips[name] = ips
                if name in vm_map:
                    vm_map[name]["phase"] = phase
                    vm_map[name]["ips"] = ips

    for name in VM_NAMES:
        info = vm_map.get(name, {})
        status = info.get("status", "NotFound")
        phase = info.get("phase", "")
        ips = info.get("ips", [])
        is_running = phase == "Running"
        checks.append({
            "group": "Virtual Machines",
            "name": f"{name} ({VM_ROLES.get(name, '')})",
            "status": "ok" if is_running else ("warn" if status == "Stopped" else "fail"),
            "detail": f"{status} | Phase: {phase}" if phase else status,
        })

    for name in VM_NAMES:
        ips = vmi_ips.get(name, [])
        for ip in ips:
            if ":" in ip:
                continue
            _, rc = run_cmd(f"ping -c 1 -W 2 {ip}")
            checks.append({
                "group": "Network Connectivity",
                "name": f"{name} ({ip})",
                "status": "ok" if rc == 0 else "fail",
                "detail": "Reachable" if rc == 0 else "Unreachable",
            })

    running_count = sum(1 for v in vm_map.values() if v.get("phase") == "Running")
    total = len(VM_NAMES)
    masters_running = sum(
        1 for n in ["twonode-master1", "twonode-master2"]
        if vm_map.get(n, {}).get("phase") == "Running"
    )
    arbiter_running = vm_map.get("twonode-arbiter", {}).get("phase") == "Running"

    if masters_running == 2 and arbiter_running:
        quorum_status = "ok"
        quorum_detail = f"Full quorum: {running_count}/{total} nodes running, all etcd members healthy"
    elif masters_running >= 1 and arbiter_running:
        quorum_status = "warn"
        quorum_detail = f"Degraded quorum: {running_count}/{total} nodes running, 1 master down but arbiter maintains quorum"
    elif masters_running == 2:
        quorum_status = "warn"
        quorum_detail = f"At risk: {running_count}/{total} nodes, arbiter down -- quorum holds but no fault tolerance"
    else:
        quorum_status = "fail"
        quorum_detail = f"Quorum lost: {running_count}/{total} nodes running"

    checks.append({
        "group": "etcd Quorum",
        "name": "Quorum Status",
        "status": quorum_status,
        "detail": quorum_detail,
    })

    pvcs = k8s_get(f"/api/v1/namespaces/{NAMESPACE}/persistentvolumeclaims")
    if "items" in pvcs:
        m3_pvcs = [p for p in pvcs["items"] if "twonode" in p["metadata"]["name"]]
        for pvc in m3_pvcs[:6]:
            name = pvc["metadata"]["name"]
            phase = pvc.get("status", {}).get("phase", "Unknown")
            storage = pvc["spec"]["resources"]["requests"].get("storage", "?")
            checks.append({
                "group": "Storage",
                "name": name,
                "status": "ok" if phase == "Bound" else "warn",
                "detail": f"{phase} ({storage})",
            })

    return {
        "hostname": "OpenShift Pod",
        "ip": os.environ.get("POD_IP", "N/A"),
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "module": "Module 3: Two-Node OpenShift Cluster",
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
    --text: #e0e0e0; --muted: #888; --accent: #e05d44;
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
    <h1>STATUS_TITLE</h1>
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
            badge = f'<span class="badge {item["status"]}">{item["status"]}</span>'
            detail = item["detail"]
            if item.get("pre"):
                detail = f'<pre class="detail">{detail}</pre>'
            else:
                detail = f'<div class="check-detail">{detail}</div>'
            body += f'<div class="check">{badge}<div><div class="check-name">{item["name"]}</div>{detail}</div></div>'
        body += "</div>"

    html = HTML_TEMPLATE
    html = html.replace("STATUS_TITLE", data["module"])
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
