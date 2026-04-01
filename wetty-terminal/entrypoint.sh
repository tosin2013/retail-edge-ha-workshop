#!/bin/bash
set -e

# Handle OpenShift arbitrary UIDs: ensure the running UID has a passwd entry
USER_ID=$(id -u)
if ! getent passwd "$USER_ID" &>/dev/null; then
    echo "student:x:${USER_ID}:0:student:/home/student:/bin/bash" >> /etc/passwd 2>/dev/null || true
fi

# Start sshd on port 2222 (localhost-only) for WeTTY to connect to.
# Uses a container-safe copy of sshd_config that is group-readable.
/usr/sbin/sshd -f /etc/ssh/sshd_config.container \
    -p 2222 \
    -o PidFile=/tmp/sshd.pid \
    -o StrictModes=no \
    -o ListenAddress=127.0.0.1 \
    -o PermitEmptyPasswords=yes \
    -o AuthorizedKeysFile=/home/student/.ssh/authorized_keys \
    2>/tmp/sshd.log || true

sleep 1

# WeTTY connects to local sshd via SSH key for passwordless auto-login.
# --force-ssh ensures SSH mode regardless of running UID.
# The Showroom chart passes --base=/wetty/ --port=8080 as container args,
# but this entrypoint ignores them to maintain full control over options.
exec wetty \
    --port 8080 \
    --base /wetty/ \
    --ssh-host 127.0.0.1 \
    --ssh-port 2222 \
    --ssh-user student \
    --ssh-key /etc/wetty-key \
    --ssh-auth publickey \
    --force-ssh \
    --allow-iframe
