#!/usr/bin/env bash
# Capture a screenshot from the VM via VNC (host-side) and via grim (in-VM)
# Usage: capture-screenshot.sh <distro>
set -euo pipefail

DISTRO="${1:?Usage: capture-screenshot.sh <distro>}"
WORK_DIR="/tmp/kvm-test/${DISTRO}"
RESULTS_DIR="test-results/${DISTRO}"
SSH_PORT=2222
SSH_HOST=127.0.0.1
SSH_USER=tester
VNC_DISPLAY=0

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
  -o BatchMode=yes
  -o LogLevel=ERROR
  -i "${WORK_DIR}/vm_key"
  -P "$SSH_PORT"
)

vm_ssh() {
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_HOST}" "$@"
}

vm_scp_from() {
  scp "${SCP_OPTS[@]}" "${SSH_USER}@${SSH_HOST}:$1" "$2"
}

echo "==> Capturing screenshots for ${DISTRO}..."

# --- Method 1: VNC screenshot from host ---
echo "--> Attempting VNC screenshot (host-side)..."
VNC_SCREENSHOT="${RESULTS_DIR}/vnc-screenshot.png"

# vncdotool for VNC capture
if command -v vncdo >/dev/null 2>&1; then
  vncdo -s "127.0.0.1::590${VNC_DISPLAY}" screenshot "$VNC_SCREENSHOT" 2>/dev/null && \
    echo "--> VNC screenshot captured" \
  || \
    echo "WARN: VNC screenshot failed, trying fallback..."
fi

# --- Method 2: grim via Wayland socket (in-VM) ---
echo "--> Attempting Wayland screenshot (in-VM via grim)..."
WAYLAND_SCREENSHOT="${RESULTS_DIR}/wayland-screenshot.png"

vm_ssh "
  # Check if a Wayland compositor is running
  WAYLAND_SOCK=\$(ls /tmp/xdg-runtime-*/wayland-* 2>/dev/null | head -1 || true)
  if [ -n \"\$WAYLAND_SOCK\" ]; then
    export XDG_RUNTIME_DIR=\$(dirname \$WAYLAND_SOCK)
    export WAYLAND_DISPLAY=\$(basename \$WAYLAND_SOCK)
    grim /tmp/grim-screenshot.png 2>/dev/null && echo 'GRIM_OK'
  else
    echo 'GRIM_SKIP: no Wayland socket'
  fi
" 2>/dev/null | grep -q "GRIM_OK" && \
  vm_scp_from "/tmp/grim-screenshot.png" "$WAYLAND_SCREENSHOT" 2>/dev/null && \
  echo "--> Wayland screenshot captured ✓" || \
  echo "WARN: in-VM Wayland screenshot skipped (compositor not running)"

# --- Collect any existing screenshots from VM ---
echo "--> Collecting screenshots from VM..."
vm_ssh "ls /tmp/hyprland-screenshot.png 2>/dev/null" 2>/dev/null && \
  vm_scp_from "/tmp/hyprland-screenshot.png" "${RESULTS_DIR}/hyprland-screenshot.png" 2>/dev/null && \
  echo "--> Hyprland headless screenshot copied ✓" || true

# --- List captured screenshots ---
echo ""
echo "==> Screenshots in ${RESULTS_DIR}:"
ls -lh "${RESULTS_DIR}"/*.png 2>/dev/null || echo "    (none captured)"
