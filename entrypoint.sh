#!/bin/bash
set -euo pipefail

# ---- Hardware-specific setup ----
case "${GPU_VENDOR:-none}" in
  nvidia)
    echo "Configuring for NVIDIA GPU..."
    mkdir -p /usr/lib/x86_64-linux-gnu/gbm
    ln -sf /usr/lib/gbm/nvidia-drm_gbm.so /usr/lib/x86_64-linux-gnu/gbm/nvidia-drm_gbm.so || true
    export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export GBM_BACKEND=nvidia-drm
    ;;
  intel|amd)
    echo "Configuring for Mesa (Intel/AMD)..."
    ;;
  none|*)
    echo "No GPU vendor specified — running without hardware acceleration."
    ;;
esac

# Auto-dump any Hyprland crash report to stdout before the container exits
dump_crash_reports() {
    for f in /root/.cache/hyprland/hyprlandCrashReport*.txt; do
        if [ -f "$f" ]; then
            echo "=================================================="
            echo "CRASH REPORT: $f"
            echo "=================================================="
            cat "$f"
            echo "=================================================="
        fi
    done
}
trap dump_crash_reports EXIT

service ssh start || true
mkdir -p /tmp/runtime-root
export XDG_RUNTIME_DIR=/tmp/runtime-root

pkill -f seatd || true
seatd -g seat &
SEATD_PID=$!
sleep 1
if ! kill -0 $SEATD_PID 2>/dev/null; then
    echo "FATAL: seatd failed to start" >&2
    exit 1
fi

pkill -f Hyprland || true
Hyprland --i-am-really-stupid &
HYPR_PID=$!

WAYLAND_DISPLAY=""
for i in $(seq 1 20); do
    SOCK=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name "wayland-*" ! -name "*.lock" 2>/dev/null | head -n1)
    if [ -n "$SOCK" ]; then
        WAYLAND_DISPLAY=$(basename "$SOCK")
        break
    fi
    if ! kill -0 $HYPR_PID 2>/dev/null; then
        echo "FATAL: Hyprland exited before creating a Wayland socket" >&2
        exit 1
    fi
    sleep 0.5
done

if [ -z "$WAYLAND_DISPLAY" ]; then
    echo "FATAL: Wayland socket never appeared after 10s" >&2
    exit 1
fi

export WAYLAND_DISPLAY
echo "Hyprland is up, WAYLAND_DISPLAY=$WAYLAND_DISPLAY"

# ponytail: exec-once in hyprland.conf does not reliably fire in this container
# (no systemd/dbus user session), so create the headless output directly instead
# of depending on it.
export HYPRLAND_INSTANCE_SIGNATURE
HYPRLAND_INSTANCE_SIGNATURE=$(ls "$XDG_RUNTIME_DIR/hypr" | head -n1)
hyprctl output create headless HEADLESS-1
hyprctl keyword monitor HEADLESS-1,1920x1080@60,auto,1

pkill -f wayvnc || true
wayvnc -o HEADLESS-1 0.0.0.0 5900 &
WAYVNC_PID=$!
sleep 1
if ! kill -0 $WAYVNC_PID 2>/dev/null; then
    echo "FATAL: wayvnc failed to start" >&2
    exit 1
fi

pkill -f websockify || true
websockify --web /opt/novnc 6080 127.0.0.1:5900 &
WEBSOCKIFY_PID=$!
sleep 1
if ! kill -0 $WEBSOCKIFY_PID 2>/dev/null; then
    echo "FATAL: websockify failed to start" >&2
    exit 1
fi

echo "All services started successfully"
wait -n
echo "A background process exited unexpectedly" >&2
exit 1