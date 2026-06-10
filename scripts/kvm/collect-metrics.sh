#!/usr/bin/env bash
# Collect performance metrics from the VM post-installation
# Usage: collect-metrics.sh <distro>
set -euo pipefail

DISTRO="${1:?Usage: collect-metrics.sh <distro>}"
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

vm_ssh() {
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_HOST}" "$@"
}

echo "==> Collecting metrics for ${DISTRO}..."

METRICS_JSON="${RESULTS_DIR}/metrics.json"
METRICS_TXT="${RESULTS_DIR}/metrics.txt"

# Gather raw metrics from VM
RAW=$(vm_ssh "
  echo '{';
  echo '\"distro\": \"'$(cat /etc/os-release | grep ^PRETTY_NAME | cut -d= -f2 | tr -d '\"')'\",';
  echo '\"kernel\": \"'$(uname -r)'\",';
  echo '\"boot_time_seconds\": '$(awk '{print $1}' /proc/uptime | cut -d. -f1)',';
  echo '\"memory_total_mb\": '$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo) ',';
  echo '\"memory_free_mb\": '$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo) ',';
  echo '\"disk_used_mb\": '$(df / --output=used 2>/dev/null | tail -1) ',';
  echo '\"disk_total_mb\": '$(df / --output=size 2>/dev/null | tail -1) ',';
  echo '\"cpu_cores\": '$(nproc) ',';
  HYPR_BIN=\$(command -v Hyprland 2>/dev/null || command -v hyprland 2>/dev/null || echo '');
  HYPR_VER=\$(\$HYPR_BIN --version 2>/dev/null | head -1 || echo 'not installed');
  echo '\"hyprland_version\": \"'\"$HYPR_VER\"'\"',';
  WAYBAR_VER=\$(waybar --version 2>/dev/null | head -1 || echo 'not installed');
  echo '\"waybar_version\": \"'\"$WAYBAR_VER\"'\"',';
  echo '\"timestamp\": \"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'\"';
  echo '}';
  " 2>/dev/null || echo '{"error": "metrics collection failed"}')

echo "$RAW" > "$METRICS_JSON"

# Also append to the flat metrics file (for GHA summary)
echo "" >> "$METRICS_TXT"
echo "# VM metrics" >> "$METRICS_TXT"
vm_ssh "
  echo 'boot_uptime_seconds='$(awk '{print int($1)}' /proc/uptime)
  echo 'memory_available_mb='$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
  echo 'disk_used_pct='$(df / --output=pcent 2>/dev/null | tail -1 | tr -d ' '')
" >> "$METRICS_TXT" 2>/dev/null || true

cat "$METRICS_JSON"
echo "==> Metrics saved to ${METP€‰M})M=9ôƒŠ
Lˆ(