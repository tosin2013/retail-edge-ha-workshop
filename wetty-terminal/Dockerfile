FROM registry.access.redhat.com/ubi9/ubi:latest

# Install Node.js, build tools, utilities, and SSH server
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
    gcc \
    gcc-c++ \
    make \
    python3 \
    openssh-server \
    openssh-clients \
    passwd \
    procps-ng \
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

# Create student user for terminal sessions
RUN useradd -m -s /bin/bash -G 0 student && \
    passwd -d student

# Configure sshd for container usage (non-privileged port, relaxed security for local-only)
RUN ssh-keygen -A && \
    mkdir -p /run/sshd && \
    sed -i 's/^#Port 22/Port 2222/' /etc/ssh/sshd_config && \
    sed -i 's/^#PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#StrictModes yes/StrictModes no/' /etc/ssh/sshd_config && \
    echo "ListenAddress 127.0.0.1" >> /etc/ssh/sshd_config

# Generate SSH key pair for WeTTY passwordless auto-login via public key auth
RUN ssh-keygen -t ed25519 -f /etc/wetty-key -N "" && \
    mkdir -p /home/student/.ssh && \
    cp /etc/wetty-key.pub /home/student/.ssh/authorized_keys && \
    chmod 700 /home/student/.ssh && \
    chmod 600 /home/student/.ssh/authorized_keys && \
    chown -R student:student /home/student/.ssh

# Make sshd files writable for OpenShift arbitrary UID (member of group 0)
# Only grant write to sshd host keys and runtime dirs, NOT ssh client config
# (ssh client is strict about permissions on its config files)
RUN chgrp -R 0 /run/sshd /home/student /etc/wetty-key /etc/wetty-key.pub && \
    chmod -R g+rwX /run/sshd /home/student && \
    chmod g+r /etc/wetty-key && \
    chmod g+rwX /etc/passwd && \
    chmod g+r /etc/ssh/ssh_host_*_key && \
    chgrp 0 /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub

# Configure shell environment for student user
RUN cp /root/.bashrc /home/student/.bashrc 2>/dev/null || true && \
    { \
    echo 'export PS1="\[\033[01;32m\]student@workshop\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "'; \
    echo 'alias k=kubectl'; \
    echo 'alias vh=virtctl'; \
    echo 'cat << "BANNER"'; \
    echo '╔══════════════════════════════════════════════════════════════════╗'; \
    echo '║        Retail Edge HA Workshop - Student Terminal               ║'; \
    echo '╚══════════════════════════════════════════════════════════════════╝'; \
    echo ''; \
    echo 'Available tools:'; \
    echo '  • oc       - OpenShift CLI'; \
    echo '  • kubectl  - Kubernetes CLI (alias: k)'; \
    echo '  • virtctl  - KubeVirt VM management (alias: vh)'; \
    echo ''; \
    echo 'Your namespace: ${STUDENT_NAMESPACE}'; \
    echo 'Student ID: ${STUDENT_ID}'; \
    echo ''; \
    echo 'Quick commands:'; \
    echo '  oc get vms -n ${STUDENT_NAMESPACE}'; \
    echo '  virtctl start <vm-name> -n ${STUDENT_NAMESPACE}'; \
    echo 'BANNER'; \
    } >> /home/student/.bashrc && \
    chown student:student /home/student/.bashrc

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENV SHELL=/bin/bash

ENTRYPOINT ["/entrypoint.sh"]
