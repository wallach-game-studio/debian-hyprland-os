#!/usr/bin/env bash
# Wait until SSH is available on the VM
# Usage: wait-for-ssh.sh <host> <port> [timeout_seconds]
set -euo pipefail

HOST="${1:?Usage: wait-for-ssh.sh <host> <port> [timeout]}"
PORT="${2:?Usage: wait-for-ssh.sh <host> <port> [timeout]}"
TIMEOUT="${3:-120}"
DISTRO="${4:-unknown}"
WORK_DIR="/tmp/kvm-test/${DISTRO}"

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=5
  -o BatchMode=yes
  -o LogLevel=ERROR
)

if [ -f "${WORK_DIR}/vm_key" ]; then
  SSH_OPTS+=(-i "${WORK_DIR}/vm_key")
fi

echo "==> Waiting for SSH on ${HOST}:${PORT} (timeout: ${TIMEOUT}s)..."
START_TIME=$(date +%s)

while true; do
  ELAPSED=$(( $(date +%s) - START_TIME ))

  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "ERROR: SSH not available after ${TIMEOUT}s"
    echo "--- Last 20 lines of serial log ---"
    if [ -f "${WORK_DIR}/serial.log" ]; then
      tail -20 "${WORK_DIR}/serial.log"
    fi
    exit 1
  fi

  if ssh "${SSH_OPTS[@]}" -p "$PORT" "tester@${HOST}" "echo ok" 2>/dev/null; then
    echo "==> SSH ready after ${ELAPSED}s ✓"
    break
  fi

  printf "    [%3ds] waiting...\r" "$ELAPSED"
  sleep 3
done

# Wait for cloud-init to fully complete
echo "--> Waiting for cloud-init to finish..."
CLOUD_INIT_TIMEOUT=60
START_TIME=$(date +%s)

while true; do
  ELAPSED=$(( $(date +%s) - START_TIME ))

  if [ "$ELAPSED" -ge "$CLOUD_INIT_TIMEOUT" ]; then
    echo "WARN: cloud-init did not finish in ${CLOUD_INIT_TIMEOUT}s, proceeding anyway"
    break
  fi

  if ssh "${SSH_OPTS[@]}" -p "$PORT" "tester@${HOST}" \
      "test -f /tmp/cloud-init-done || cloud-init status 2>/dev/null | grep -q done" 2>/dev/null; then
    echo "--> cloud-init done ✓"
    break
  fi

  sleep 3
done
