#!/bin/bash
# Install flightctl CLI from Edge Manager deployment
# Runs on first login; skips if already installed.

if [ -f /usr/local/bin/flightctl ]; then
  exit 0
fi

EM_NS="${EDGE_MANAGER_NAMESPACE:-redhat-edge-manager}"

# Method 1: Download from cli-artifacts route
CLI_ROUTE=$(oc get route -n "$EM_NS" flightctl-cli-artifacts-route -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$CLI_ROUTE" ]; then
  wget -q --no-check-certificate "https://${CLI_ROUTE}/linux/amd64/flightctl-linux-amd64.tar.gz" \
    -O /tmp/flightctl.tar.gz 2>/dev/null
  if [ -f /tmp/flightctl.tar.gz ] && file /tmp/flightctl.tar.gz | grep -q gzip; then
    tar xzf /tmp/flightctl.tar.gz -C /tmp/ 2>/dev/null
    if [ -f /tmp/flightctl ]; then
      chmod +x /tmp/flightctl
      mv /tmp/flightctl /usr/local/bin/flightctl 2>/dev/null
      rm -f /tmp/flightctl.tar.gz
      exit 0
    fi
  fi
  rm -f /tmp/flightctl.tar.gz
fi

# Method 2: Copy from cli-artifacts pod
CLI_POD=$(oc get pods -n "$EM_NS" -o name 2>/dev/null | grep cli-artifacts | head -1)
if [ -n "$CLI_POD" ]; then
  POD_NAME="${CLI_POD#pod/}"
  oc exec -n "$EM_NS" "$POD_NAME" -- cat /home/server/src/gh-archives/amd64/linux/flightctl-linux-amd64.tar.gz \
    > /tmp/flightctl.tar.gz 2>/dev/null
  if [ -f /tmp/flightctl.tar.gz ] && file /tmp/flightctl.tar.gz | grep -q gzip; then
    tar xzf /tmp/flightctl.tar.gz -C /tmp/ 2>/dev/null
    if [ -f /tmp/flightctl ]; then
      chmod +x /tmp/flightctl
      mv /tmp/flightctl /usr/local/bin/flightctl 2>/dev/null
      rm -f /tmp/flightctl.tar.gz
      exit 0
    fi
  fi
  rm -f /tmp/flightctl.tar.gz
fi
