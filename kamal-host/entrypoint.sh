#!/bin/sh
set -e

# Make the bind-mounted docker socket readable by anyone (the macOS host
# socket has perms/owners that don't map cleanly into the Linux container).
if [ -S /var/run/docker.sock ]; then
  chmod 666 /var/run/docker.sock 2>/dev/null || true
fi

exec /usr/sbin/sshd -D -e
