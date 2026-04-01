FROM docker.io/wettyoss/wetty:latest

USER root

# Install dependencies
RUN apk add --no-cache \
    curl \
    bash \
    bash-completion \
    jq \
    git

# Install glibc for oc/kubectl binaries (Alpine uses musl, but oc/kubectl need glibc)
RUN curl -L https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub -o /etc/apk/keys/sgerrand.rsa.pub && \
    curl -L https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.35-r1/glibc-2.35-r1.apk -o /tmp/glibc.apk && \
    curl -L https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.35-r1/glibc-bin-2.35-r1.apk -o /tmp/glibc-bin.apk && \
    apk add --no-cache /tmp/glibc.apk /tmp/glibc-bin.apk && \
    rm /tmp/glibc.apk /tmp/glibc-bin.apk

# Download and install CLI tools
RUN curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz -o /tmp/oc.tar.gz && \
    tar xzf /tmp/oc.tar.gz -C /usr/local/bin/ oc kubectl && \
    rm -f /tmp/oc.tar.gz /tmp/README.md && \
    curl -L https://github.com/kubevirt/kubevirt/releases/download/v1.4.0/virtctl-v1.4.0-linux-amd64 -o /usr/local/bin/virtctl && \
    chmod +x /usr/local/bin/oc /usr/local/bin/kubectl /usr/local/bin/virtctl && \
    ls -la /usr/local/bin/ | grep -E '(oc|kubectl|virtctl)'

# Configure shell environment
# Note: Skipping bash completion for oc/kubectl due to glibc compatibility issues in Alpine
# The binaries work fine at runtime, just can't generate completion during build
RUN echo 'export PATH=/usr/local/bin:$PATH' >> /root/.bashrc && \
    echo 'export PS1="\[\033[01;32m\]student@workshop\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> /root/.bashrc && \
    echo 'alias k=kubectl' >> /root/.bashrc && \
    echo 'alias vh=virtctl' >> /root/.bashrc

# Add welcome message
RUN echo 'cat << "EOF"' >> /root/.bashrc && \
    echo '╔══════════════════════════════════════════════════════════════════╗' >> /root/.bashrc && \
    echo '║        Retail Edge HA Workshop - Student Terminal               ║' >> /root/.bashrc && \
    echo '╚══════════════════════════════════════════════════════════════════╝' >> /root/.bashrc && \
    echo '' >> /root/.bashrc && \
    echo 'Available tools:' >> /root/.bashrc && \
    echo '  • oc       - OpenShift CLI' >> /root/.bashrc && \
    echo '  • kubectl  - Kubernetes CLI (alias: k)' >> /root/.bashrc && \
    echo '  • virtctl  - KubeVirt VM management (alias: vh)' >> /root/.bashrc && \
    echo '' >> /root/.bashrc && \
    echo 'Your namespace: ${STUDENT_NAMESPACE}' >> /root/.bashrc && \
    echo 'Student ID: ${STUDENT_ID}' >> /root/.bashrc && \
    echo '' >> /root/.bashrc && \
    echo 'Quick commands:' >> /root/.bashrc && \
    echo '  oc get vms -n ${STUDENT_NAMESPACE}' >> /root/.bashrc && \
    echo '  virtctl start <vm-name> -n ${STUDENT_NAMESPACE}' >> /root/.bashrc && \
    echo 'EOF' >> /root/.bashrc

USER node

# Default to bash shell (WeTTY will spawn this)
ENV SHELL=/bin/bash
