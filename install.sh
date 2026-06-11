#!/usr/bin/env bash
# Hyprland Desktop Environment Installer
# Supports: Debian 12 (Bookworm) | Ubuntu 24.04 LTS (Noble)
#
# Usage:
#   sudo bash install.sh
#   sudo bash install.sh --non-interactive   (for CI/automation)
#   sudo bash install.sh --skip-nvidia       (skip GPU detection)
#
# Issues: https://github.com/wallach-game-studio/debian-hyprland-os/issues

set -euo pipefail

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
NON_INTERACTIVE=false
SKIP_NVIDIA=false

for arg in "$@"; do
  case "$arg" in
    --non-interactive) NON_INTERACTIVE=true ;;
    --skip-nvidia)     SKIP_NVIDIA=true ;;
  esac
done

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

log()  { echo -e "${GREEN}[+]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Root check
# ---------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "This script must be run as root. Use: sudo bash $0"

# ---------------------------------------------------------------------------
# Distro detection
# ---------------------------------------------------------------------------
detect_distro() {
  if [ ! -f /etc/os-release ]; then
    die "Cannot detect OS: /etc/os-release not found"
  fi

  # shellcheck source=/dev/null
  . /etc/os-release

  DISTRO_ID="${ID:-unknown}"
  DISTRO_VERSION="${VERSION_ID:-unknown}"
  DISTRO_CODENAME="${VERSION_CODENAME:-unknown}"

  case "${DISTRO_ID}:${DISTRO_VERSION}" in
    debian:12) info "Detected: Debian 12 (Bookworm)" ;;
    ubuntu:24.04) info "Detected: Ubuntu 24.04 LTS (Noble)" ;;
    *)
      warn "Unsupported distro: ${DISTRO_ID} ${DISTRO_VERSION}"
      if $NON_INTERACTIVE; then
        die "Aborting on unsupported distro in non-interactive mode"
      fi
      read -rp "Continue anyway? [y/N] " answer
      [[ "$answer" =~ ^[Yy]$ ]] || die "Aborted."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Package installation helpers
# ---------------------------------------------------------------------------
apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

apt_update() {
  apt-get update -q
}

# ---------------------------------------------------------------------------
# Phase 1: Base packages
# ---------------------------------------------------------------------------
install_base() {
  log "Installing base packages..."
  apt_update
  apt_install \
    curl wget git ca-certificates gnupg \
    build-essential \
    software-properties-common \
    xz-utils \
    xdg-utils \
    dbus \
    pipewire pipewire-pulse \
    wireplumber \
    policykit-1 \
    xwayland \
    seatd

  # Hyprland (via aquamarine/libseat) needs an active seat to open
  # DRM/input devices. Without systemd-logind (e.g. no session/no VT,
  # such as over SSH), libseat falls back to its 'builtin' backend, which
  # can't open any devices and aquamarine fails with "no GPUs"/"could not
  # start". seatd provides a seat without requiring logind or a VT.
  systemctl enable --now seatd 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Phase 1: Hyprland (issue #1 / #2)
# ---------------------------------------------------------------------------
# Neither Debian 12 nor Ubuntu 24.04 ship a libwayland new enough for any
# Hyprland release built against the hypr* ecosystem (Hyprland >= 0.36
# requires wayland-server >= 1.22.90, but Debian 12 has 1.21.0 and Ubuntu
# 24.04 has 1.22.0), so apt and from-source builds are both dead ends.
# Instead, install a prebuilt Hyprland from nixpkgs (nixos-24.11), which is
# fully cached on cache.nixos.org and requires no local compilation.
install_hyprland() {
  log "Installing Hyprland from nixpkgs (prebuilt binaries, no compilation)..."

  local TARGET_USER="${SUDO_USER:-$USER}"
  local HOME_DIR
  HOME_DIR=$(getent passwd "$TARGET_USER" | cut -d: -f6)
  local NIXPKGS_URL="https://channels.nixos.org/nixos-24.11/nixexprs.tar.xz"

  if [ ! -d /nix ]; then
    mkdir -m 0755 /nix
    chown "${TARGET_USER}:${TARGET_USER}" /nix
  fi

  if [ ! -x "${HOME_DIR}/.nix-profile/bin/nix-env" ]; then
    log "Installing Nix package manager (single-user) for ${TARGET_USER}..."
    sudo -u "$TARGET_USER" sh -c 'curl -fsSL https://nixos.org/nix/install | sh -s -- --no-daemon'
  fi

  log "Fetching Hyprland from cache.nixos.org (prebuilt, ~250MB)..."
  sudo -u "$TARGET_USER" bash -c \
    ". '${HOME_DIR}/.nix-profile/etc/profile.d/nix.sh' && nix-env -f '${NIXPKGS_URL}' -iA hyprland"

  log "Linking Hyprland binaries into /usr/local/bin..."
  for bin in Hyprland hyprctl hyprpm; do
    ln -sf "${HOME_DIR}/.nix-profile/bin/${bin}" "/usr/local/bin/${bin}"
  done

  # Hyprland/aquamarine needs a DRM device (/dev/dri/cardN) and a render
  # node (/dev/dri/renderD*) for its GBM-based allocator, plus the 'seat'
  # group for libseat to talk to seatd.
  log "Granting ${TARGET_USER} access to DRM/input/seat devices..."
  usermod -aG video,render,input,seat "$TARGET_USER" 2>/dev/null || true

  # `modprobe` lives in kmod, which minimal/cloud images don't always have.
  apt_install kmod

  # Cloud kernels often don't auto-load the GPU driver. virtio_gpu provides
  # /dev/dri/cardN (KMS/scanout) on QEMU's virtio-vga; load it if missing.
  if ! ls /dev/dri/card* >/dev/null 2>&1; then
    log "No DRM device found — loading virtio_gpu..."
    if modprobe virtio_gpu 2>/dev/null; then
      udevadm settle
      echo virtio_gpu > /etc/modules-load.d/virtio_gpu.conf
    else
      warn "virtio_gpu unavailable"
    fi
  fi

  # Aquamarine's headless backend is mandatory and requires a render node.
  # Real GPUs already provide one; VMs without a GPU (e.g. virtio-vga
  # without virgl) don't, so fall back to vgem (a software render node).
  if ! ls /dev/dri/renderD* >/dev/null 2>&1; then
    log "No DRM render node found — loading vgem for headless rendering..."
    if modprobe vgem 2>/dev/null; then
      udevadm settle
      echo vgem > /etc/modules-load.d/vgem.conf
    else
      warn "vgem unavailable; Hyprland may fail to start without a GPU"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Phase 1: Core components (issues #3-#6)
# ---------------------------------------------------------------------------
install_components() {
  log "Installing Waybar (issue #4)..."
  apt_install waybar

  log "Installing Rofi (issue #3)..."
  apt_install rofi

  log "Installing Dunst (issue #5)..."
  apt_install dunst libnotify-bin

  log "Installing terminal & file manager (issue #6)..."
  apt_install alacritty 2>/dev/null || apt_install foot || warn "No preferred terminal found"
  apt_install thunar 2>/dev/null || apt_install pcmanfm || warn "No file manager found"

  log "Installing screenshot & UI tools..."
  apt_install grim slurp wl-clipboard \
    swaylock swayidle \
    brightnessctl \
    playerctl 2>/dev/null || warn "Some optional tools not installed"
}

# ---------------------------------------------------------------------------
# Phase 1: Copy configs (issues #2-#6)
# ---------------------------------------------------------------------------
install_configs() {
  local TARGET_USER="${SUDO_USER:-$USER}"
  local HOME_DIR
  HOME_DIR=$(getent passwd "$TARGET_USER" | cut -d: -f6)

  log "Installing configs for user: ${TARGET_USER} (${HOME_DIR})..."

  # Hyprland
  local HYPR_CONFIG="${HOME_DIR}/.config/hypr"
  mkdir -p "$HYPR_CONFIG"
  if [ -d "configs/hyprland" ] && [ "$(ls -A configs/hyprland 2>/dev/null)" ]; then
    cp -r configs/hyprland/. "$HYPR_CONFIG/"
  else
    cat > "${HYPR_CONFIG}/hyprland.conf" << 'HYPRCONF'
# Hyprland config - debian-hyprland-os
# See: https://wiki.hyprland.org/Configuring/

$terminal = alacritty
$menu = rofi -show drun

monitor = ,preferred,auto,1

exec-once = waybar
exec-once = dunst

input {
    kb_layout = us
    follow_mouse = 1
    touchpad { natural_scroll = true }
}

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee)
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}

bind = SUPER, Return, exec, $terminal
bind = SUPER, Space, exec, $menu
bind = SUPER, Q, killactive
bind = SUPER SHIFT, Q, exit
bind = SUPER, F, fullscreen
bind = SUPER, 1, workspace, 1
bind = SUPER, 2, workspace, 2
bind = SUPER, 3, workspace, 3
bind = SUPER, 4, workspace, 4
bind = SUPER, 5, workspace, 5
HYPRCONF
  fi
  chown -R "${TARGET_USER}:${TARGET_USER}" "$HYPR_CONFIG"

  # Waybar
  local WAYBAR_CONFIG="${HOME_DIR}/.config/waybar"
  mkdir -p "$WAYBAR_CONFIG"
  if [ -d "configs/waybar" ] && [ "$(ls -A configs/waybar 2>/dev/null)" ]; then
    cp -r configs/waybar/. "$WAYBAR_CONFIG/"
  fi
  chown -R "${TARGET_USER}:${TARGET_USER}" "$WAYBAR_CONFIG"

  # Rofi
  local ROFI_CONFIG="${HOME_DIR}/.config/rofi"
  mkdir -p "$ROFI_CONFIG"
  if [ -d "configs/rofi" ] && [ "$(ls -A configs/rofi 2>/dev/null)" ]; then
    cp -r configs/rofi/. "$ROFI_CONFIG/"
  fi
  chown -R "${TARGET_USER}:${TARGET_USER}" "$ROFI_CONFIG"

  # Dunst
  local DUNST_CONFIG="${HOME_DIR}/.config/dunst"
  mkdir -p "$DUNST_CONFIG"
  if [ -d "configs/dunst" ] && [ "$(ls -A configs/dunst 2>/dev/null)" ]; then
    cp -r configs/dunst/. "$DUNST_CONFIG/"
  fi
  chown -R "${TARGET_USER}:${TARGET_USER}" "$DUNST_CONFIG"

  # Alacritty
  local ALACRITTY_CONFIG="${HOME_DIR}/.config/alacritty"
  mkdir -p "$ALACRITTY_CONFIG"
  if [ -d "configs/alacritty" ] && [ "$(ls -A configs/alacritty 2>/dev/null)" ]; then
    cp -r configs/alacritty/. "$ALACRITTY_CONFIG/"
  fi
  chown -R "${TARGET_USER}:${TARGET_USER}" "$ALACRITTY_CONFIG"

  # Thunar
  local THUNAR_CONFIG="${HOME_DIR}/.config/Thunar"
  mkdir -p "$THUNAR_CONFIG"
  if [ -d "configs/thunar" ] && [ "$(ls -A configs/thunar 2>/dev/null)" ]; then
    cp -r configs/thunar/. "$THUNAR_CONFIG/"
  fi
  chown -R "${TARGET_USER}:${TARGET_USER}" "$THUNAR_CONFIG"
}

# ---------------------------------------------------------------------------
# Phase 1: Nvidia detection (issue #7)
# ---------------------------------------------------------------------------
install_nvidia_if_present() {
  $SKIP_NVIDIA && return 0

  if ! lspci | grep -qi nvidia; then
    info "No Nvidia GPU detected, skipping Nvidia setup"
    return 0
  fi

  log "Nvidia GPU detected — installing proprietary driver..."

  local NVIDIA_PACKAGES=(
    nvidia-driver
    firmware-misc-nonfree
    nvidia-settings
    nvidia-vaapi-driver
    libva-nvidia-driver
  )

  case "${DISTRO_ID}:${DISTRO_VERSION}" in
    ubuntu:24.04)
      NVIDIA_PACKAGES=(nvidia-driver-550 nvidia-settings nvidia-vaapi-driver)
      ;;
    debian:12)
      apt_install nvidia-detect 2>/dev/null || true
      NVIDIA_GPU=$(lspci -nn | grep -i nvidia | head -1 | grep -oP '\[\d{4}:\d{4}\]' | tr -d '[]')
      if [ -n "$NVIDIA_GPU" ]; then
        log "Nvidia GPU device ID: ${NVIDIA_GPU}"
      fi
      ;;
  esac

  apt_install "${NVIDIA_PACKAGES[@]}" || {
    warn "Some Nvidia packages failed to install"
    warn "Try: sudo apt-get install nvidia-driver"
  }

  log "Configuring Hyprland for Nvidia..."
  local TARGET_USER="${SUDO_USER:-$USER}"
  local HOME_DIR
  HOME_DIR=$(getent passwd "$TARGET_USER" | cut -d: -f6)
  local HYPR_CONFIG="${HOME_DIR}/.config/hypr"
  mkdir -p "$HYPR_CONFIG"

  local NVIDIA_ENV_FILE="${HYPR_CONFIG}/nvidia.conf"
  cat > "$NVIDIA_ENV_FILE" << 'NVNCONF'
# Nvidia-specific Hyprland configuration
# Source: https://wiki.hyprland.org/Nvidia/

env = LIBVA_DRIVER_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = NVD_BACKEND,direct
env = WLR_NO_HARDWARE_CURSORS,1

cursor {
  no_hardware_cursors = true
}
NVNCONF

  if [ -f "${HYPR_CONFIG}/hyprland.conf" ]; then
    grep -q "source = nvidia.conf" "${HYPR_CONFIG}/hyprland.conf" 2>/dev/null || \
      echo -e "\n# Nvidia support (auto-generated)\nsource = nvidia.conf" >> "${HYPR_CONFIG}/hyprland.conf"
  fi
  chown -R "${TARGET_USER}:${TARGET_USER}" "$HYPR_CONFIG"

  log "Nvidia setup complete — reboot recommended"
}

# ---------------------------------------------------------------------------
# Verify installation
# ---------------------------------------------------------------------------
verify_install() {
  log "Verifying installation..."
  local ERRORS=0

  for cmd in Hyprland waybar rofi dunst; do
    if command -v "$cmd" >/dev/null 2>&1; then
      info "  $cmd OK"
    else
      warn "  $cmd not found"
      ERRORS=$(( ERRORS + 1 ))
    fi
  done

  if [ "$ERRORS" -gt 0 ]; then
    warn "${ERRORS} component(s) not found - installation may be incomplete"
    return 1
  fi

  log "All core components verified"
  return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo ""
  echo "=================================="
  echo "  Debian Hyprland OS - Installer  "
  echo "=================================="
  echo

  detect_distro
  install_base
  install_hyprland
  install_components
  install_configs
  install_nvidia_if_present
  verify_install

  echo
  log "Installation complete!"
  info "Log out and select Hyprland from your display manager, or run: Hyprland"
}

main "$@"
