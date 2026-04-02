FROM registry.access.redhat.com/ubi9/ubi:latest

# Install utilities
RUN dnf install -y \
    wget \
    tar \
    gzip \
    bash \
    bash-completion \
    jq \
    git \
    procps-ng \
    && dnf clean all

# Install ttyd (web-based terminal, no SSH needed)
RUN wget -q https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 -O /usr/local/bin/ttyd && \
    chmod +x /usr/local/bin/ttyd

# Install CLI tools
RUN wget -q https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz && \
    tar xzf openshift-client-linux.tar.gz && \
    mv oc kubectl /usr/local/bin/ && \
    rm openshift-client-linux.tar.gz && \
    wget -q https://github.com/kubevirt/kubevirt/releases/download/v1.4.0/virtctl-v1.4.0-linux-amd64 && \
    chmod +x virtctl-v1.4.0-linux-amd64 && \
    mv virtctl-v1.4.0-linux-amd64 /usr/local/bin/virtctl

# Install flightctl CLI (Red Hat Edge Manager)
COPY flightctl /usr/local/bin/flightctl
RUN chmod +x /usr/local/bin/flightctl

# Create student home directory for OpenShift arbitrary UID
RUN mkdir -p /home/student && \
    chmod g+rwX /home/student && \
    chgrp -R 0 /home/student && \
    chmod g+rwX /etc/passwd

# Configure shell environment
RUN { \
    echo 'export PS1="\[\033[01;32m\]student@workshop\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "'; \
    echo 'alias k=kubectl'; \
    echo 'alias vh=virtctl'; \
    echo 'cat << "BANNER"'; \
    echo '╔══════════════════════════════════════════════════════════════════╗'; \
    echo '║        Retail Edge HA Workshop - Student Terminal               ║'; \
    echo '╚══════════════════════════════════════════════════════════════════╝'; \
    echo ''; \
    echo 'Available tools:'; \
    echo '  • oc        - OpenShift CLI'; \
    echo '  • kubectl   - Kubernetes CLI (alias: k)'; \
    echo '  • virtctl   - KubeVirt VM management (alias: vh)'; \
    echo '  • flightctl - Red Hat Edge Manager CLI'; \
    echo ''; \
    echo 'Your namespace: ${STUDENT_NAMESPACE}'; \
    echo 'Student ID: ${STUDENT_ID}'; \
    echo ''; \
    echo 'Quick commands:'; \
    echo '  oc get vms -n ${STUDENT_NAMESPACE}'; \
    echo '  virtctl start <vm-name> -n ${STUDENT_NAMESPACE}'; \
    echo '  flightctl get devices'; \
    echo 'BANNER'; \
    } > /home/student/.bashrc && \
    chmod 644 /home/student/.bashrc && \
    chgrp 0 /home/student/.bashrc

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENV SHELL=/bin/bash
ENV HOME=/home/student

ENTRYPOINT ["/entrypoint.sh"]
