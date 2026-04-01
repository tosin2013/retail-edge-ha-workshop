#!/bin/bash

# Handle OpenShift arbitrary UIDs: ensure the running UID has a passwd entry
USER_ID=$(id -u)
if ! getent passwd "$USER_ID" &>/dev/null; then
    echo "student:x:${USER_ID}:0:student:/home/student:/bin/bash" >> /etc/passwd 2>/dev/null || true
fi

export HOME=/home/student
cd "$HOME"

# Run ttyd on port 8080 at the /wetty/ base path.
# The Showroom chart passes --base=/wetty/ --port=8080 as container args,
# but this entrypoint ignores them; ttyd serves the terminal directly
# without SSH and with no authentication prompt.
exec ttyd -W -p 8080 -b /wetty/ bash --login
