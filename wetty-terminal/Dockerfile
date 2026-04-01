FROM registry.access.redhat.com/ubi9/ubi:latest

# Install Node.js and tools
RUN dnf install -y \
    nodejs \
    npm \
    wget \
    tar \
    gzip \
    bash \
    bash-completion \
    jq \
    git \
    && dnf clean all

# Install WeTTY
RUN npm install -g wetty

# Install CLI tools
RUN wget -q https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz && \
    tar xzf openshift-client-linux.tar.gz && \
    mv oc kubectl /usr/local/bin/ && \
    rm openshift-client-linux.tar.gz && \
    wget -q https://github.com/kubevirt/kubevirt/releases/download/v1.4.0/virtctl-v1.4.0-linux-amd64 && \
    chmod +x virtctl-v1.4.0-linux-amd64 && \
    mv virtctl-v1.4.0-linux-amd64 /usr/local/bin/virtctl

# Configure shell environment
RUN echo 'export PS1="\[\033[01;32m\]student@workshop\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> /root/.bashrc && \
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

EXPOSE 8080

# Use default shell (bash)
ENV SHELL=/bin/bash

# Start WeTTY in non-SSH mode (direct shell access)
CMD ["wetty", "--port", "8080", "--base", "/wetty/", "--command", "/bin/bash"]
