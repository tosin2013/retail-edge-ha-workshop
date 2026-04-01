FROM registry.access.redhat.com/ubi9/ubi:latest

# Install SSH server and essential tools
RUN dnf install -y \
    openssh-server \
    openssh-clients \
    wget \
    tar \
    gzip \
    vim \
    bash-completion \
    jq \
    git \
    && dnf clean all

# Install OpenShift CLI (oc and kubectl)
RUN wget -q https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz && \
    tar xzf openshift-client-linux.tar.gz && \
    mv oc kubectl /usr/local/bin/ && \
    rm openshift-client-linux.tar.gz && \
    oc completion bash > /etc/bash_completion.d/oc && \
    kubectl completion bash > /etc/bash_completion.d/kubectl

# Install virtctl (KubeVirt CLI)
RUN wget -q https://github.com/kubevirt/kubevirt/releases/download/v1.4.0/virtctl-v1.4.0-linux-amd64 && \
    chmod +x virtctl-v1.4.0-linux-amd64 && \
    mv virtctl-v1.4.0-linux-amd64 /usr/local/bin/virtctl

# Create student user with known password
RUN useradd -m -s /bin/bash student && \
    echo "student:redhat" | chpasswd

# Configure SSH server
RUN ssh-keygen -A && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/GSSAPIAuthentication yes/GSSAPIAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config

# Configure helpful student environment
RUN echo 'export PS1="\[\033[01;32m\]student@workshop\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> /home/student/.bashrc && \
    echo 'alias k=kubectl' >> /home/student/.bashrc && \
    echo 'alias vh=virtctl' >> /home/student/.bashrc && \
    echo 'source /etc/bash_completion.d/oc' >> /home/student/.bashrc && \
    echo 'source /etc/bash_completion.d/kubectl' >> /home/student/.bashrc && \
    echo 'export KUBECONFIG=/var/run/secrets/kubernetes.io/serviceaccount/.kubeconfig' >> /home/student/.bashrc && \
    chown -R student:student /home/student

# Create directory for kubeconfig
RUN mkdir -p /var/run/secrets/kubernetes.io/serviceaccount && \
    chown -R student:student /var/run/secrets/kubernetes.io/serviceaccount

# Add welcome message
RUN echo '#!/bin/bash' > /etc/profile.d/welcome.sh && \
    echo 'cat << "EOF"' >> /etc/profile.d/welcome.sh && \
    echo '╔══════════════════════════════════════════════════════════════════╗' >> /etc/profile.d/welcome.sh && \
    echo '║        Retail Edge HA Workshop - Student Terminal               ║' >> /etc/profile.d/welcome.sh && \
    echo '╚══════════════════════════════════════════════════════════════════╝' >> /etc/profile.d/welcome.sh && \
    echo '' >> /etc/profile.d/welcome.sh && \
    echo 'Available tools:' >> /etc/profile.d/welcome.sh && \
    echo '  • oc       - OpenShift CLI' >> /etc/profile.d/welcome.sh && \
    echo '  • kubectl  - Kubernetes CLI (alias: k)' >> /etc/profile.d/welcome.sh && \
    echo '  • virtctl  - KubeVirt VM management (alias: vh)' >> /etc/profile.d/welcome.sh && \
    echo '' >> /etc/profile.d/welcome.sh && \
    echo 'Your namespace: ${STUDENT_NAMESPACE}' >> /etc/profile.d/welcome.sh && \
    echo 'Student ID: ${STUDENT_ID}' >> /etc/profile.d/welcome.sh && \
    echo '' >> /etc/profile.d/welcome.sh && \
    echo 'Quick commands:' >> /etc/profile.d/welcome.sh && \
    echo '  oc get vms -n ${STUDENT_NAMESPACE}' >> /etc/profile.d/welcome.sh && \
    echo '  virtctl start <vm-name> -n ${STUDENT_NAMESPACE}' >> /etc/profile.d/welcome.sh && \
    echo 'EOF' >> /etc/profile.d/welcome.sh && \
    chmod +x /etc/profile.d/welcome.sh

EXPOSE 22

# Start SSH daemon in foreground
CMD ["/usr/sbin/sshd", "-D", "-e"]
