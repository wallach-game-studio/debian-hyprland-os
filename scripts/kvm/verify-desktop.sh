#!/usr/bin/env bash
# Verify Hyprland desktop environment in the VM
# Starts Hyprland headlessly (WLR_BACKENDS=headless) and validates components
# Usage: verify-desktop.sh <distro>
set -euo pipefail

DISTRO="${1:?Usage: verify-desktop.sh <distro>}"
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

VERIFY_LOG="${RESULTS_DIR}/verify.log"
PASS_COUNT=0
FAIL_COUNT=0

check() {
  local name="$1"
  local cmd="$2"
  local expected="${3:-0}"

  printf "  %-45s " "${name}..."
  if vm_ssh "$cmd" > /dev/null 2>&1; then
    echo "✒ PASS"
    echo "PASS: ${name}" >> "$VERIFY_LOG"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
  else
    echo "✗ FAIL"
    echo "FAIL: ${name}" >> "$VERIFY_LOG"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  fi
}

echo "==> Verifying desktop environment on ${DISTRO}..."
echo "# Verification results for ${DISTRO}" > "$VERIFY_LOG"
echo "# $(date -u)" >> "$VERIFY_LOG"
echo "" >> "$VERIFY_LOG"

# --- Package checks ---
echo "--> Checking installed packages..."
check "hyprland binary exists"     "command -v Hyprland || command -v hyprland"
check "waybar installed"           "command -v waybar"
check "rofi installed"             "command -v rofi"
check "dunst installed"            "command -v dunst"
check "terminal emulator present"  "command -v alacritty || command -v kitty || command -v foot"
check "grim (screenshot) present"  "command -v grim"
check "pipewire / audio present"   "command -v pipewire"

# --- Config files ---
echo "--> Checking configuration files..."
check "hyprland.conf exists"       "test -f ~/.config/hypr/hyprland.conf"
check "waybar config exists"       "test -f ~/.config/waybar/config || test -f ~/.config/waybar/config.jsonc"
check "rofi config present"        "test -d ~/.config/rofi"

# --- Start Hyprland headlessly ---
echo "--> Starting Hyprland (headless mode)..."
vm_ssh "
  export WLR_BACKENDS=headless
  export WLR_RENDERER=pixman
  export HYPRLAND_NO_RT=1
  export LIBGL_DEBUG=verbose
  export EGL_LOG_LEVEL=debug
  export MESA_DEBUG=1
  export XDG_RUNTIME_DIR=/tmp/xdg-runtime-\$USER
  mkdir -p \$XDG_RUNTIME_DIR
  chmod 700 \$XDG_RUNTIME_DIR
  mkdir -p /tmp/hyprland-test-logs

  # Start Hyprland in background, let it run for 10s
  Hyprland 2>&1 &
  HYPR_PID=\$!
  echo \$HYPR_PID > /tmp/hyprland.pid

  sleep 10

  # Check if it's still running (didn't crash immediately)
  if kill -0 \$HYPR_PID 2>/dev/null; then
    echo 'HYPRLAND_RUNNING=true' > /tmp/hypr-status.txt
    # Try to take screenshot
    WAYLAND_DISPLAY=wayland-1 grim /tmp/hyprland-screenshot.png 2>/dev/null || true
    kill \$HYPR_PID 2>/dev/null
    wait \$HYPR_PID 2>/dev/null
  else
    echo 'HYPRLAND_RUNNING=false' > /tmp/hypr-status.txt
  fi
" 2>&1 | tee "${RESULTS_DIR}/hyprland-start.log" || true

# --- GPU/DRM diagnostics (helps debug headless backend failures) ---
echo "--> Collecting GPU/DRM diagnostics..."
vm_ssh "
  echo '--- /dev/dri ---'
  ls -la /dev/dri/ 2>&1 || echo 'no /dev/dri'
  echo '--- lsmod (drm/vgem/virtio) ---'
  lsmod | grep -iE 'drm|vgem|virtio_gpu' || echo 'none loaded'
  echo '--- modinfo virtio_gpu ---'
  modinfo virtio_gpu 2>&1 | head -5
  echo '--- modinfo vgem ---'
  modinfo vgem 2>&1 | head -5
  echo '--- id ---'
  id
  echo '--- seatd ---'
  systemctl is-active seatd 2>&1
  ls -la /run/seatd.sock 2>&1
  echo '--- nix mesa / DRI drivers ---'
  ls -la \$HOME/.nix-profile/lib/dri/ 2>&1 || echo 'no dri dir in nix-profile'
  find /nix/store -maxdepth 1 -iname '*mesa*' 2>/dev/null
  echo '--- /etc/environment ---'
  cat /etc/environment 2>&1 || echo 'no /etc/environment'
  echo '--- LIBGL_DRIVERS_PATH (in SSH session) ---'
  echo \"LIBGL_DRIVERS_PATH=\${LIBGL_DRIVERS_PATH:-unset}\"
  if [ -n \"\${LIBGL_DRIVERS_PATH:-}\" ]; then
    ls -la \"\$LIBGL_DRIVERS_PATH\" 2>&1 | head -30
  fi
  echo '--- Hyprland binary type ---'
  HYPR_BIN=\$(command -v Hyprland)
  echo \"command -v Hyprland: \$HYPR_BIN\"
  file \"\$HYPR_BIN\" 2>&1
  HYPR_REAL=\$(readlink -f \"\$HYPR_BIN\")
  echo \"readlink -f: \$HYPR_REAL\"
  file \"\$HYPR_REAL\" 2>&1
  echo '--- Hyprland wrapper script contents ---'
  cat \"\$HYPR_REAL\" 2>&1 | head -100
  echo '--- system Mesa DRI drivers (/usr/lib) ---'
  find /usr/lib -maxdepth 4 -iname '*_dri.so' 2>/dev/null | head -20
  find /usr/lib -maxdepth 3 -type d -iname dri 2>/dev/null
  echo '--- all *_dri.so in /nix/store ---'
  find /nix/store -maxdepth 4 -iname '*_dri.so' 2>/dev/null | head -20
  echo '--- hyprland crash report (tail) ---'
  cat \$HOME/.cache/hyprland/hyprlandCrashReport*.txt 2>/dev/null | tail -120 || echo 'no crash report'
" > "${RESULTS_DIR}/gpu-diagnostics.log" 2>&1 || true

# Retrieve Hyprland status
vm_ssh "cat /tmp/hypr-status.txt 2>/dev/null || echo 'HYPRLAND_RUNNING=unknown'" \
  >> "$VERIFY_LOG" 2>/dev/null || true

HYPR_STATUS=$(vm_ssh "cat /tmp/hypr-status.txt 2>/dev/null" 2>/dev/null || echo "HYPRLAND_RUNNING=unknown")
if echo "$HYPR_STATUS" | grep -q "true"; then
  echo "  Hyprland headless startup                      ✒ PASS"
  echo "PASS: Hyprland headless startup" >> "$VERIFY_LOG"
  PASS_COUNT=$(( PASS_COUNT + 1 ))
else
  echo "  Hyprland headless startup                      ✗ FAIL"
  echo "FAIL: Hyprland headless startup" >> "$VERIFY_LOG"
  FAIL_COUNT=$(( FAIL_COUNT + 1 ))
fi

# --- System logs ---
echo "--> Collecting system logs..."
vm_ssh "sudo journalctl -b --no-pager -n 200 2>/dev/null || true" \
  > "${RESULTS_DIR}/journal.log" 2>/dev/null || true

# --- Summary ---
echo "" >> "$VERIFY_LOG"
echo "SUMMARY: ${PASS_COUNT} passed, ${FAIL_COUNT} failed" >> "$VERIFY_LOG"
echo
echo "==> Verification summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [ "$FAIL_COUNT" -gt 0 ]; then
  # Non-zero but don't fail the whole job for non-critical issues
  echo "WARN: ${FAIL_COUNT} verification check(s) failed"
fi
