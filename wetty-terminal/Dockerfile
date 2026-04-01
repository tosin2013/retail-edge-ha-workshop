FROM docker.io/wettyoss/wetty:latest

USER root

# Install OpenShift CLI tools
RUN apk add --no-cache \
    curl \
    bash \
    bash-completion \
    jq \
    git && \
    # Download oc/kubectl
    curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz | tar xz -C /usr/local/bin/ && \
    # Download virtctl
    curl -L https://github.com/kubevirt/kubevirt/releases/download/v1.4.0/virtctl-v1.4.0-linux-amd64 -o /usr/local/bin/virtctl && \
    chmod +x /usr/local/bin/virtctl && \
    # Setup bash completion
    oc completion bash > /etc/bash_completion.d/oc && \
    kubectl completion bash > /etc/bash_completion.d/kubectl

# Configure shell environment
RUN echo 'export PS1="\[\033[01;32m\]student@workshop\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> /root/.bashrc && \
    echo 'alias k=kubectl' >> /root/.bashrc && \
    echo 'alias vh=virtctl' >> /root/.bashrc && \
    echo 'source /etc/bash_completion.d/oc 2>/dev/null' >> /root/.bashrc && \
    echo 'source /etc/bash_completion.d/kubectl 2>/dev/null' >> /root/.bashrc

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
