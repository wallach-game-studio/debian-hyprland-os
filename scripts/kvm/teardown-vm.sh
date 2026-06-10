#!/usr/bin/env bash
# Gracefully stop and clean up a KVM test VM
# Usage: teardown-vm.sh <distro>
set -euo pipefail

DISTRO="${1:?Usage: teardown-vm.sh <distro>}"
WORK_DIR="/tmp/kvm-test/${DISTRO}"
SSH_PORT=2222
SSH_HOST=127.0.0.1
SSH_USER=tester

echo "==> Tearing down VM: ${DISTRO}..."

# --- Graceful shutdown via SSH" ---
if [ -f "${WORK_DIR}/vm_key" ]; then
  SSH_OPTS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=5
    -o BatchMode=yes
    -o LogLevel=ERROR
    -i "${WORK_DIR}/vm_key"
    -p "$SSH_PORT"
  )

  echo "--> Sending graceful shutdown..."
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_HOST}" \
    "sudo systemctl poweroff" 2>/dev/null || true

  sleep 5
fi

# --- Force kill if still running ---
if [ -f "${WORK_DIR}/vm.pid" ]; then
  VM_PID=$(cat "${WORK_DIR}/vm.pid" 2>/dev/null || echo "")
  if [ -n "$VM_PID" ] && kill -0 "$VM_PID" 2>/dev/null; then
    echo "--> Force killing VM (PID: ${VM_PID})..."
    kill -TERM "$VM_PID" 2>/dev/null || true
    sleep 2
    kill -KILL "$VM_PID" 2>/dev/null || true
  fi
  rm -f "${WORK_DIR}/vm.pid"
fi

# --- Cleanup work dir ---
echo "--> Cleaning up work directory..."
rm -rf "${WORK_DIR}"

echo "==> VM ${DISTRO} torn down ✓"
