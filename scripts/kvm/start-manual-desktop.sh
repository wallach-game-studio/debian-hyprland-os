#!/usr/bin/env bash
# Restart the VM's console session so the manual VNC tester lands directly on
# a logged-in Hyprland desktop instead of a login prompt.
# provision-vm.sh sets up autologin + an auto-exec-Hyprland snippet in
# ~/.profile, but they only take effect once the console session is
# (re)started - and Hyprland isn't installed yet when the VM first boots.
# Restarting getty@tty1 here (after install.sh has run) re-triggers the
# autologin and starts Hyprland on the real DRM/KMS display.
# Usage: start-manual-desktop.sh <distro>
set -euo pipefail

DISTRO="${1:?Usage: start-manual-desktop.sh <distro>}"
WORK_DIR="/tmp/kvm-test/${DISTRO}"
SSH_PORT=2222
SSH_HOST=127.0.0.1
SSH_USER=tester

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10
  -o BatchMode=yes
  -o LogLevel=ERROR
  -i "${WORK_DIR}/vm_key"
  -p "$SSH_PORT"
)

vm_ssh() {
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_HOST}" "$@"
}

echo "==> Starting Hyprland on the console of ${DISTRO} for manual testing..."
vm_ssh "sudo systemctl restart getty@tty1" || true

echo "--> Waiting for Hyprland to come up on tty1..."
sleep 10

echo "--> Console processes matching 'hypr':"
vm_ssh "pgrep -afi hypr" || echo "  (none found - console may still show a login shell)"
