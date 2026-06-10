#!/usr/bin/env bash
# Copy repo into VM and run install.sh — capture logs and exit code
# Usage: run-install-test.sh <distro>
set -euo pipefail

DISTRO="${1:?Usage: run-install-test.sh <distro>}"
WORK_DIR="/tmp/kvm-test/${DISTRO}"
RESULTS_DIR="test-results/${DISTRO}"
SSH_PORT=2222
SSH_HOST=127.0.0.1
SSH_USER=tester

mkdir -p "$RESULTS_DIR"

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10
  -o BatchMode=yes
  -o LogLevel=ERROR
  -i "${WORK_DIR}/vm_key"
  -p "$SSH_PORT"
)

SCP_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10
  -o BatchMode=yes
  -o LogLevel=ERROR
  -i "${WORK_DIR}/vm_key"
  -P "$SSH_PORT"
)

vm_ssh() {
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_HOST}" "$@"
}

vm_scp_to() {
  scp -r "${SCP_OPTS[@]}" "$1" "${SSH_USER}@${SSH_HOST}:$2"
}

vm_scp_from() {
  scp "${SCP_OPTS[@]}" "${SSH_USER}@${SSH_HOST}:$1" "$2"
}

echo "==> Running installation test on ${DISTRO}..."

# --- Copy repo to VM ---
echo "--> Copying repository to VM..."
vm_ssh "mkdir -p ~/debian-hyprland-os"
vm_scp_to "." "~/debian-hyprland-os/"

# --- Record system info ---
echo "--> Collecting pre-install system info..."
vm_ssh "
  echo '=== OS Release ===' > /tmp/pre-install.log
  cat /etc/os-release >> /tmp/pre-install.log
  echo '=== Memory ===' >> /tmp/pre-install.log
  free -h >> /tmp/pre-install.log
  echo '=== Disk ===' >> /tmp/pre-install.log
  df -h >> /tmp/pre-install.log
  echo '=== CPU ===' >> /tmp/pre-install.log
  nproc >> /tmp/pre-install.log
"
vm_scp_from "/tmp/pre-install.log" "${RESULTS_DIR}/pre-install.log"

# --- Run install.sh ---
echo "--> Starting install.sh (non-interactive)..."
INSTALL_START=$(date +%s)

# Run with timeout (30 min max), capture stdout+stderr
set +e
vm_ssh "
  cd ~/debian-hyprland-os
  chmod +x install.sh
  sudo DEBIAN_FRONTEND=noninteractive CI=true bash install.sh --non-interactive > /tmp/install.log 2>&1
  INSTALL_EXIT=\$?
  cat /tmp/install.log
  echo \"EXIT_CODE=\${INSTALL_EXIT}\"
  exit \$INSTALL_EXIT
" 2>&1 | tee "${RESULTS_DIR}/install.log"
INSTALL_RC=${PIPESTATUS[0]}
set -e

INSTALL_ELAPSED=$(( $(date +%s) - INSTALL_START ))
echo "--> install.sh finished in ${INSTALL_ELAPSED}s (exit: ${INSTALL_RC})"

# Copy install log from VM (in case SSH tee missed something)
vm_scp_from "/tmp/install.log" "${RESULTS_DIR}/install-vm.log" 2>/dev/null || true

# Record timing
echo "install_time_seconds=${INSTALL_ELAPSED}" >> "${RESULTS_DIR}/metrics.txt"
echo "install_exit_code=${INSTALL_RC}" >> "${RESULTS_DIR}/metrics.txt"

if [ "$INSTALL_RC" -ne 0 ]; then
  echo "ERROR: install.sh exited with code ${INSTALL_RC}"
  # Collect journalctl for debugging
  vm_ssh "sudo journalctl -n 100 --no-pager 2>/dev/null || true" \
    > "${RESULTS_DIR}/journal-on-fail.log" 2>/dev/null || true
  exit "$INSTALL_RC"
fi

echo "==> Installation completed successfully ✓"
echo "PASS: install.sh completed in ${INSTALL_ELAPSED}s" >> "${RESULTS_DIR}/install.log"
