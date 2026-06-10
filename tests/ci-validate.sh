#!/usr/bin/env bash
# CI validation: run this on any machine (no root, no KVM needed)
# to verify install.sh structure, config files, and script syntax.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $*"; }

check() {
  local label="$1"; shift
  if "$@" > /dev/null 2>&1; then
    pass
  else
    fail "$label"
  fi
}

echo "========================================="
echo "  CI Validation — debian-hyprland-os"
echo "========================================="

# --- 1. Shell syntax ---
echo ""
echo "--- Shell syntax ---"
for f in "$ROOT/install.sh" "$ROOT"/scripts/kvm/*.sh; do
  check "bash -n $(basename "$f")" bash -n "$f"
done

# --- 2. Config files present ---
echo ""
echo "--- Config files ---"
check "hyprland/hyprland.conf"  test -f "$ROOT/configs/hyprland/hyprland.conf"
check "waybar/config.jsonc"     test -f "$ROOT/configs/waybar/config.jsonc"
check "waybar/style.css"        test -f "$ROOT/configs/waybar/style.css"
check "rofi/config.rasi"        test -f "$ROOT/configs/rofi/config.rasi"
check "dunst/dunstrc"           test -f "$ROOT/configs/dunst/dunstrc"
check "alacritty/alacritty.toml" test -f "$ROOT/configs/alacritty/alacritty.toml"

# --- 3. KVM scripts present ---
echo ""
echo "--- KVM scripts ---"
for s in provision-vm wait-for-ssh run-install-test verify-desktop capture-screenshot collect-metrics teardown-vm; do
  check "scripts/kvm/${s}.sh" test -f "$ROOT/scripts/kvm/${s}.sh"
done

# --- 4. GitHub Actions workflow ---
echo ""
echo "--- CI workflow ---"
check ".github/workflows/test-installation.yml" test -f "$ROOT/.github/workflows/test-installation.yml"

# --- 5. install.sh flag parsing ---
echo ""
echo "--- install.sh flag parsing ---"
# Read the flag parsing block from install.sh directly
FLAG_BLOCK=$(sed -n '/^NON_INTERACTIVE/,/^done$/p' "$ROOT/install.sh" 2>/dev/null || true)
grep -q "NON_INTERACTIVE=false" <<< "$FLAG_BLOCK" && pass || fail "install.sh: NON_INTERACTIVE default"
grep -q "SKIP_NVIDIA=false" <<< "$FLAG_BLOCK" && pass || fail "install.sh: SKIP_NVIDIA default"
grep -q "non-interactive" <<< "$FLAG_BLOCK" && pass || fail "install.sh: --non-interactive flag defined"
grep -q "skip-nvidia" <<< "$FLAG_BLOCK" && pass || fail "install.sh: --skip-nvidia flag defined"

# --- 6. install.sh function definitions ---
echo ""
echo "--- install.sh functions ---"
for fn in detect_distro apt_install apt_update install_base install_hyprland install_components install_configs install_nvidia_if_present verify_install main; do
  grep -q "^[[:space:]]*${fn}()" "$ROOT/install.sh" && pass || fail "function ${fn}() not found"
done

# --- 7. Keybindings have sensible defaults ---
echo ""
echo "--- Config sanity ---"
grep -q 'mainMod' "$ROOT/configs/hyprland/hyprland.conf" && pass || fail "hyprland.conf: mainMod defined"
grep -q 'alacritty' "$ROOT/configs/hyprland/hyprland.conf" && pass || fail "hyprland.conf: terminal set"
grep -q 'rofi' "$ROOT/configs/hyprland/hyprland.conf" && pass || fail "hyprland.conf: menu launcher set"
grep -q 'waybar' "$ROOT/configs/hyprland/hyprland.conf" && pass || fail "hyprland.conf: exec waybar"

# --- 8. Nvidia config block in install.sh ---
echo ""
echo "--- Nvidia support ---"
grep -q "nvidia-driver" "$ROOT/install.sh" && pass || fail "install.sh: nvidia-driver reference"
grep -q "nvidia.conf" "$ROOT/install.sh" && pass || fail "install.sh: nvidia.conf generation"

# --- 9. README ---
echo ""
echo "--- Documentation ---"
check "README.md exists" test -f "$ROOT/README.md"
grep -q "Debian 12" "$ROOT/README.md" && pass || fail "README.md: mentions Debian 12"
grep -qi "Keybindings" "$ROOT/README.md" && pass || fail "README.md: has keybindings section"

# --- Summary ---
echo ""
echo "========================================="
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "========================================="
exit $FAIL
