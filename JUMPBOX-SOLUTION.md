# Jumpbox/Bastion Pod Solution for Showroom Terminal

## Overview

Instead of fighting with terminal images (WeTTY vs ttyd), deploy a **bastion/jumpbox pod** in OpenShift that students SSH into from the Showroom terminal. This is a common Showroom pattern used in many Red Hat workshops.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Student Browser                                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Showroom (showroom-student-01 namespace)            │   │
│  │ ├── Lab Guide (Content)                            │   │
│  │ ├── WeTTY Terminal (stays as-is)                   │   │
│  │ └── Proxy                                           │   │
│  └─────────────────────────────────────────────────────┘   │
│           │                                                 │
│           │ SSH (port 22)                                   │
│           ↓                                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Jumpbox Pod (student namespace)                     │   │
│  │ ├── SSH Server (sshd)                              │   │
│  │ ├── oc CLI (pre-installed)                         │   │
│  │ ├── virtctl CLI (pre-installed)                    │   │
│  │ ├── kubectl (pre-installed)                        │   │
│  │ ├── ServiceAccount Token (auto-mounted)            │   │
│  │ └── User: student, Auth: password or key          │   │
│  └─────────────────────────────────────────────────────┘   │
│           │                                                 │
│           │ oc/virtctl commands                             │
│           ↓                                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ OpenShift API / KubeVirt VMs                        │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Why This Solves the Problem

| Issue | Jumpbox Solution |
|-------|------------------|
| WeTTY asks for username | ✅ Give it one! SSH to jumpbox pod |
| No oc/virtctl tools | ✅ Pre-installed in jumpbox image |
| Image compatibility issues | ✅ Use standard WeTTY (no changes needed) |
| Authentication complexity | ✅ Simple SSH password or use OpenShift SA tokens |
| Tool version management | ✅ Single image to maintain |
| Multi-workshop reuse | ✅ Same jumpbox for any workshop |

## Implementation

### 1. Create Jumpbox Docker Image

**Dockerfile:**
```dockerfile
FROM registry.access.redhat.com/ubi9/ubi:latest

# Install SSH server and tools
RUN dnf install -y \
    openssh-server \
    openssh-clients \
    wget \
    tar \
    gzip \
    vim \
    tmux \
    bash-completion \
    && dnf clean all

# Install OpenShift CLI
RUN wget -q https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz && \
    tar xzf openshift-client-linux.tar.gz && \
    mv oc kubectl /usr/local/bin/ && \
    rm openshift-client-linux.tar.gz && \
    oc completion bash > /etc/bash_completion.d/oc

# Install virtctl
RUN wget -q https://github.com/kubevirt/kubevirt/releases/download/v1.4.0/virtctl-v1.4.0-linux-amd64 && \
    chmod +x virtctl-v1.4.0-linux-amd64 && \
    mv virtctl-v1.4.0-linux-amd64 /usr/local/bin/virtctl

# Create student user
RUN useradd -m -s /bin/bash student && \
    echo "student:redhat" | chpasswd

# Configure SSH
RUN ssh-keygen -A && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/GSSAPIAuthentication yes/GSSAPIAuthentication no/' /etc/ssh/sshd_config

# Create directory for ServiceAccount token
RUN mkdir -p /var/run/secrets/kubernetes.io/serviceaccount

# Add helpful student environment
RUN echo 'export PS1="\[\033[01;32m\]student@workshop\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> /home/student/.bashrc && \
    echo 'alias k=kubectl' >> /home/student/.bashrc && \
    echo 'source /etc/bash_completion.d/oc' >> /home/student/.bashrc && \
    chown -R student:student /home/student

EXPOSE 22

# Start SSH daemon
CMD ["/usr/sbin/sshd", "-D", "-e"]
```

**Build and Push:**
```bash
# Build image
podman build -t quay.io/YOUR_USERNAME/workshop-jumpbox:latest .

# Push to public registry
podman login quay.io
podman push quay.io/YOUR_USERNAME/workshop-jumpbox:latest

# Make repository public in quay.io web UI
```

### 2. Deploy Jumpbox Pod Per Student

**Helm Template:** `helm/retail-edge-ha/templates/jumpbox/jumpbox-deployment.yaml`

```yaml
{{- if .Values.jumpbox.enabled }}
{{- range $studentNum := until (int .Values.students.count) }}
{{- $studentId := add $studentNum 1 | printf "%02d" }}
{{- $namespace := printf "%s-%s-%s" $.Values.students.namespacePrefix $.Values.students.userbase $studentId }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jumpbox-sa
  namespace: {{ $namespace }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jumpbox-admin
  namespace: {{ $namespace }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: admin
subjects:
- kind: ServiceAccount
  name: jumpbox-sa
  namespace: {{ $namespace }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jumpbox
  namespace: {{ $namespace }}
  labels:
    app: jumpbox
    student-id: "{{ $studentId }}"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jumpbox
  template:
    metadata:
      labels:
        app: jumpbox
    spec:
      serviceAccountName: jumpbox-sa
      containers:
      - name: jumpbox
        image: {{ $.Values.jumpbox.image }}
        ports:
        - containerPort: 22
          name: ssh
        env:
        - name: STUDENT_ID
          value: "{{ $studentId }}"
        - name: STUDENT_NAMESPACE
          value: "{{ $namespace }}"
        - name: STUDENT_USER
          value: "{{ $.Values.students.userbase }}-{{ $studentId }}"
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        volumeMounts:
        - name: kubeconfig
          mountPath: /home/student/.kube
      volumes:
      - name: kubeconfig
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: jumpbox
  namespace: {{ $namespace }}
  labels:
    app: jumpbox
spec:
  selector:
    app: jumpbox
  ports:
  - port: 22
    targetPort: 22
    name: ssh
  type: ClusterIP
{{- end }}
{{- end }}
```

### 3. Update values.yaml

**Add to `helm/retail-edge-ha/values.yaml`:**

```yaml
# Jumpbox Configuration
# -----------------------------------------------------------------------------
jumpbox:
  # Enable jumpbox pod deployment (provides terminal access with pre-installed tools)
  enabled: true

  # Jumpbox container image
  image: quay.io/YOUR_USERNAME/workshop-jumpbox:latest

  # Credentials
  username: student
  password: redhat  # Consider using Secret in production

  # Resource limits per jumpbox
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "500m"
```

### 4. Configure WeTTY to Connect to Jumpbox

**Update Showroom App Template:** `helm/retail-edge-ha/templates/apps/showroom-app.yaml`

Add these Helm parameters (lines 44-52):

```yaml
      # Terminal configuration - SSH to jumpbox pod
      - name: terminal.image
        value: {{ $.Values.showroom.terminal.image }}
      - name: terminal.envVars.SSHHOST
        value: "jumpbox.{{ $studentNamespace }}.svc.cluster.local"
      - name: terminal.envVars.SSHPORT
        value: "22"
      - name: terminal.envVars.SSHUSER
        value: "{{ $.Values.jumpbox.username }}"
      - name: terminal.envVars.SSHPASS
        value: "{{ $.Values.jumpbox.password }}"
      - name: terminal.envVars.STUDENT_ID
        value: "{{ $studentId }}"
```

**Result:** WeTTY will automatically SSH to the jumpbox pod with pre-configured credentials!

### 5. Deploy and Test

```bash
# 1. Update values.yaml
cat >> helm/retail-edge-ha/values.yaml <<EOF

# Jumpbox terminal access
jumpbox:
  enabled: true
  image: quay.io/YOUR_USERNAME/workshop-jumpbox:latest
  username: student
  password: redhat
EOF

# 2. Commit and push
git add helm/retail-edge-ha/
git commit -m "Add jumpbox pod for terminal access with pre-installed tools"
git push origin main

# 3. Trigger ArgoCD sync
oc annotate application.argoproj.io retail-edge-ha -n openshift-gitops \
  argocd.argoproj.io/refresh=normal --overwrite

# 4. Wait for jumpbox pods to deploy
oc get pods -n retail-edge-student-01 | grep jumpbox

# 5. Test SSH access from local machine (should work)
oc port-forward -n retail-edge-student-01 svc/jumpbox 2222:22
ssh -p 2222 student@localhost  # Password: redhat

# 6. Test from Showroom terminal (should auto-login)
# Open Showroom URL in browser - terminal should connect automatically
```

## Advantages of Jumpbox Approach

### ✅ **Solves All Terminal Issues**

- No authentication prompt (WeTTY connects to jumpbox automatically)
- All CLI tools pre-installed (oc, virtctl, kubectl)
- Uses standard WeTTY image (no custom terminal image needed)
- Compatible with Showroom deployer chart v0.4.9 (no modifications)

### ✅ **Better Architecture**

- Separation of concerns: Terminal UI vs execution environment
- Easy to upgrade tools (just rebuild jumpbox image)
- Can customize environment per workshop
- Students get isolated shell environment
- ServiceAccount tokens auto-mounted for OpenShift access

### ✅ **Reusable Across Workshops**

- Same jumpbox image for multiple workshops
- Add workshop-specific tools via init containers
- Centralized tool version management
- Single image to maintain

### ✅ **Production-Ready Features**

- SSH access from anywhere (not just Showroom)
- Can enable SSH key authentication instead of passwords
- Audit logging via SSH
- Resource limits per student
- Can integrate with LDAP/OAuth for auth

## Security Considerations

### Current Implementation (Dev/Workshop):
- Password authentication: `student:redhat`
- Simple and works for workshops
- Students isolated by namespace RBAC

### Production Hardening (Optional):

1. **SSH Key Authentication:**
   ```yaml
   # Generate keys per student
   ssh-keygen -t ed25519 -f student-$STUDENTID -N ''

   # Mount as Secret
   - name: ssh-keys
     secret:
       secretName: student-{{ $studentId }}-ssh-keys
   ```

2. **Disable Password Auth:**
   ```dockerfile
   RUN sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
   ```

3. **Use ServiceAccount Tokens:**
   ```bash
   # In jumpbox entrypoint
   export KUBECONFIG=/var/run/secrets/kubernetes.io/serviceaccount/kubeconfig
   oc login --token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
   ```

## Comparison: Jumpbox vs Custom Terminal Image

| Aspect | Jumpbox Approach | Custom Terminal Image |
|--------|------------------|----------------------|
| **Complexity** | Low - standard components | Medium - custom image build |
| **Showroom Compatibility** | ✅ Works with standard WeTTY | ❌ Requires chart modifications |
| **Tool Management** | ✅ One image, easy updates | ❌ Need to rebuild terminal image |
| **Authentication** | ✅ Standard SSH | ❌ Complex workarounds |
| **Reusability** | ✅ Same jumpbox for any workshop | ❌ Each workshop needs custom image |
| **SSH Access** | ✅ From anywhere | ❌ Only via Showroom |
| **Resource Usage** | +256Mi RAM per student | No additional resources |
| **Implementation Time** | 2-3 hours | 2-3 hours |
| **Maintenance** | ✅ Low - standard SSH | ❌ Medium - custom entrypoints |

## Cost Analysis

**Per-Student Resources:**
- Jumpbox pod: 256Mi RAM, 100m CPU (request)
- For 25 students: 6.4Gi RAM, 2.5 CPU
- Negligible compared to VM workloads (each student: 32Gi RAM, 16 CPU)

**Worth it?** Absolutely yes - fixes terminal issues permanently with minimal overhead.

## Migration Path

### Phase 1: Deploy Jumpbox (Immediate)
1. Build jumpbox image
2. Add Helm templates
3. Configure WeTTY to connect
4. Deploy via ArgoCD

**Result:** Terminal works with all tools pre-installed

### Phase 2: Enhance (Optional)
1. Add SSH key auth
2. Integrate audit logging
3. Add workshop-specific tools
4. Enable SSH access from local machines

## Alternative: Shared Jumpbox (Cost Optimization)

Instead of 1 jumpbox per student, use 1 shared jumpbox with user isolation:

```yaml
# Single jumpbox pod
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workshop-jumpbox
  namespace: retail-edge-workshop
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: jumpbox
        image: quay.io/YOUR_USERNAME/workshop-jumpbox:latest
        resources:
          requests:
            memory: "2Gi"
            cpu: "1000m"
```

**Dockerfile changes:**
```dockerfile
# Create users for all students
RUN for i in $(seq -w 1 25); do \
    useradd -m -s /bin/bash student-$i && \
    echo "student-$i:redhat-$i" | chpasswd; \
    done
```

**Trade-offs:**
- ✅ Lower resource usage (2Gi vs 25 × 256Mi = 6.4Gi)
- ❌ Shared environment (students can see each other)
- ❌ Security concerns (students share pod)

**Recommendation:** Use per-student jumpbox for workshops (better isolation).

## Conclusion

**The jumpbox approach is the BEST solution for Showroom terminal access because:**

1. ✅ Uses standard components (no hacks)
2. ✅ Solves authentication problem elegantly
3. ✅ Pre-installs all CLI tools
4. ✅ Minimal resource overhead
5. ✅ Reusable across workshops
6. ✅ Easy to maintain and upgrade
7. ✅ Production-ready architecture

**Recommendation:** Implement jumpbox solution as the permanent fix for terminal access in this workshop and all future Showroom workshops.

## Next Steps

1. **Build jumpbox image** (1 hour)
2. **Add Helm templates** (30 minutes)
3. **Test with 1 student** (30 minutes)
4. **Deploy to all students** (15 minutes)
5. **Verify terminal access works** (15 minutes)

**Total: 2-3 hours to fully working solution**

Ready to proceed with jumpbox implementation?
