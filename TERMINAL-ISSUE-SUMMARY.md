# Showroom Terminal Authentication Issue - Analysis & Solutions

## Issue Summary

The Showroom terminal is prompting for username/password login instead of providing immediate shell access, blocking all students from using the workshop.

## Root Cause Analysis

### What We Discovered

1. **Current Configuration**: Terminal uses `docker.io/wettyoss/wetty:latest`
2. **WeTTY Behavior**: WeTTY is a web-based SSH terminal that REQUIRES authentication
3. **Missing Config**: No `SSHUSER`, `SSHHOST`, or credentials configured in deployment
4. **Result**: Login prompt appears asking for username

### Why Simple Image Swap Fails

**Attempted Fix #1**: `quay.io/openshiftlabs/showroom-terminal:latest`
- ❌ Result: Image pull failed - unauthorized (private registry)

**Attempted Fix #2**: `docker.io/tsl0922/ttyd:latest`
- ❌ Result: Container crashes - `exec --base=/wetty/ failed: Permission denied`
- **Reason**: Showroom deployer chart v0.4.9 passes WeTTY-specific arguments
- ttyd doesn't understand `--base=/wetty/` command-line argument
- The Showroom Helm chart is hard-coded for WeTTY compatibility

### Architecture Constraint

The Showroom deployer chart (v0.4.9) from `https://rhpds.github.io/showroom-deployer` is designed to work with WeTTY and passes these arguments:
```
--base=/wetty/ --port=8080
```

Simply changing the container image breaks compatibility because:
- ttyd uses different command syntax: `ttyd [options] <command>`
- WeTTY uses: `wetty [options]` then SSH's to a host
- The chart's hardcoded arguments are incompatible between the two

## Viable Solutions

### Option 1: Custom WeTTY Configuration (Quickest Workaround)

**Approach**: Configure WeTTY to auto-login with environment variables

**Implementation**:
1. Keep using `docker.io/wettyoss/wetty:latest`
2. Create a custom entrypoint script that:
   - Sets SSHUSER=root (or creates a user)
   - Sets SSHHOST=localhost
   - Configures PAM for passwordless login
   - Starts sshd in the container
   - Launches WeTTY to connect to localhost

**Pros**:
- Works with existing Showroom chart
- No chart modifications needed
- Can include oc/virtctl in custom image

**Cons**:
- Requires building custom Docker image
- More complex (SSH daemon + PAM config)
- Need accessible image registry

**Estimated Effort**: 2-3 hours to build and test

### Option 2: Fork/Patch Showroom Deployer Chart

**Approach**: Modify the Showroom Helm chart to support ttyd

**Implementation**:
1. Fork `https://github.com/rhpds/showroom-deployer`
2. Add conditional logic for ttyd vs WeTTY
3. Use ttyd-specific args when terminal.type != "wetty"
4. Host patched chart in accessible Helm repo
5. Update values.yaml to use patched chart

**Pros**:
- Clean ttyd integration
- Can upstream to Showroom project
- Future-proof solution

**Cons**:
- Requires Helm chart expertise
- Need to maintain fork
- Longer implementation time

**Estimated Effort**: 4-6 hours + maintenance overhead

### Option 3: Use OpenShift Web Console Instead

**Approach**: Skip embedded terminal, use native OpenShift console

**Implementation**:
1. Set `showroom.terminal.enabled: false` in values.yaml
2. Update student guides to use OpenShift web console
3. Students access VMs via: Console → Virtualization → VMs → Console tab
4. Document `virtctl` CLI usage from local machine (optional)

**Pros**:
- No custom images needed
- No authentication issues
- Full OpenShift UI features available
- Simpler architecture

**Cons**:
- Students need separate browser tabs
- Less integrated experience
- Requires students to understand web console navigation

**Estimated Effort**: 1-2 hours (documentation updates only)

### Option 4: Build Custom ttyd-Compatible Image ⭐ RECOMMENDED

**Approach**: Create Docker image with ttyd + oc/virtctl, bypassing WeTTY args

**Implementation**:
```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

# Install ttyd
RUN microdnf install -y wget tar gzip && \
    wget https://github.com/tsl0922/ttyd/releases/download/1.7.4/ttyd.x86_64 && \
    chmod +x ttyd.x86_64 && mv ttyd.x86_64 /usr/local/bin/ttyd

# Install oc and virtctl
RUN wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz && \
    tar xzf openshift-client-linux.tar.gz && \
    mv oc kubectl /usr/local/bin/ && \
    wget https://github.com/kubevirt/kubevirt/releases/download/v1.4.0/virtctl-v1.4.0-linux-amd64 && \
    chmod +x virtctl-v1.4.0-linux-amd64 && mv virtctl-v1.4.0-linux-amd64 /usr/local/bin/virtctl

# Create entrypoint that ignores WeTTY args and runs ttyd
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
```

**entrypoint.sh**:
```bash
#!/bin/bash
# Ignore all WeTTY args (--base, --port, etc) and run ttyd
exec ttyd -p 8080 bash
```

**Pros**:
- Works with existing Showroom chart (ignores incompatible args)
- Includes oc/virtctl pre-installed
- No authentication prompt
- Can host on docker.io or quay.io (public)

**Cons**:
- Requires Docker image build/push
- Need accessible registry

**Estimated Effort**: 1-2 hours

## Recommendation

**Use Option 4: Custom ttyd-compatible image**

### Why This is Best:

1. **Minimal changes**: Only update values.yaml image reference
2. **No chart modifications**: Works with existing Showroom v0.4.9
3. **Full CLI support**: oc and virtctl pre-installed
4. **No authentication**: Immediate shell access
5. **Public hosting**: Can push to docker.io/quay.io

### Implementation Steps:

```bash
# 1. Create Dockerfile and entrypoint
mkdir -p ~/retail-edge-terminal-image
cd ~/retail-edge-terminal-image

cat > Dockerfile <<'EOF'
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

RUN microdnf install -y wget tar gzip bash && \
    microdnf clean all

# Install ttyd
RUN wget -q https://github.com/tsl0922/ttyd/releases/download/1.7.4/ttyd.x86_64 && \
    chmod +x ttyd.x86_64 && mv ttyd.x86_64 /usr/local/bin/ttyd

# Install OpenShift CLI
RUN wget -q https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz && \
    tar xzf openshift-client-linux.tar.gz && \
    mv oc kubectl /usr/local/bin/ && \
    rm openshift-client-linux.tar.gz

# Install virtctl
RUN wget -q https://github.com/kubevirt/kubevirt/releases/download/v1.4.0/virtctl-v1.4.0-linux-amd64 && \
    chmod +x virtctl-v1.4.0-linux-amd64 && \
    mv virtctl-v1.4.0-linux-amd64 /usr/local/bin/virtctl

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
EOF

cat > entrypoint.sh <<'EOF'
#!/bin/bash
# Ignore WeTTY-specific args and run ttyd with bash
exec ttyd -p 8080 bash
EOF

# 2. Build and push image
podman build -t quay.io/YOUR_USERNAME/showroom-terminal:latest .
podman login quay.io
podman push quay.io/YOUR_USERNAME/showroom-terminal:latest

# Make repository public in quay.io web UI

# 3. Update values.yaml
# Change line 361:
#   image: quay.io/YOUR_USERNAME/showroom-terminal:latest

# 4. Deploy
git add helm/retail-edge-ha/values.yaml
git commit -m "Use custom ttyd terminal image with oc/virtctl"
git push origin main
```

## Current Status

**✅ Committed Changes**:
- values.yaml updated to use `docker.io/tsl0922/ttyd:latest`
- Documentation added to DEPLOYMENT.md and STUDENT-ACCESS.md
- Changes pushed to GitHub

**❌ Deployment Status**:
- ttyd pod crashing due to incompatible WeTTY arguments
- Reverted to WeTTY (terminal still asks for username)

**🔧 Immediate Action Needed**:
- Build custom Docker image (Option 4)
- OR implement Option 3 (use web console instead)

## Timeline Estimates

| Option | Build Time | Deploy Time | Total | Complexity |
|--------|-----------|-------------|-------|------------|
| Option 1 (Custom WeTTY) | 2-3h | 30min | 3-4h | Medium |
| Option 2 (Fork chart) | 4-6h | 1h | 5-7h | High |
| Option 3 (Web console) | 1-2h | 15min | 2h | Low |
| **Option 4 (Custom ttyd)** | **1-2h** | **15min** | **2-3h** | **Low-Medium** |

## Decision Required

Please choose one of the following:

1. **Build custom ttyd image** (Option 4) - Recommended, 2-3h total
2. **Use web console instead** (Option 3) - Fastest, 2h total
3. **Continue with WeTTY** and document "terminal not available, use web console"

Let me know which approach you'd like to proceed with!
