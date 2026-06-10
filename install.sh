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
    xdg-utils \
    dbus \
    pipewire pipewire-audio \
    wireplumber \
    polkit \
    xwayland
}

# ---------------------------------------------------------------------------
# Phase 1: Hyprland (issue #1 / #2)
# ---------------------------------------------------------------------------
install_hyprland() {
  log "Installing Hyprland..."

  case "${DISTRO_ID}:${DISTRO_VERSION}" in
    ubuntu:24.04)
      apt_install hyprland
      ;;
    debian:12)
      warn "Hyprland not in Debian 12 stable repos, using upstream script..."
      install_hyprland_from_source_debian12
      ;;
    *)
      warn "Unknown distro - attempting generic apt install..."
      apt_install hyprland || warn "Hyprland not found in repos, manual install needed"
      ;;
  esac
}

install_hyprland_from_source_debian12() {
  grep -q "contrib" /etc/apt/sources.list || \
    sed -i 's/main$/main contrib non-free non-free-firmware/' /etc/apt/sources.list
  apt_update

  apt_install \
    meson cmake ninja-build \
    libwayland-dev libwayland-egl-backend-dev \
    libxkbcommon-dev libinput-dev \
    libudev-dev libpixman-1-dev \
    libseatd-dev libvulkan-dev libvulkan-volk-dev \
    libegl-dev libgles-dev \
    libxcb-dri3-dev libxcb-present-dev \
    glslang-tools \
    libdisplay-info-dev \
    libtomlplusplus-dev \
    hyprutils-dev hyprlang-dev \
    hyprwayland-scanner \
    aquamarine-dev

  # TODO(issue #1): Clone and build Hyprland from source
  warn "TODO: Hyprland source build for Debian 12 - not yet implemented"
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
bind = SUPER, F, zullscreen
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
}

# ---------------------------------------------------------------------------
# Phase 1: Nvidia detection (issue #7)
# ---------------------------------------------------------------------------
install_nvidia_if_present() {
  $SKIP_NVIDIA && return 0

  if lspci | grep -qi nvidia; then
    log "Nvidia GPU detected (issue #7)..."
    warn "Nvidia driver installation - TODO (issue #7, not yet implemented)"
    # TODO(issue #7): install nvidia-driver, configure Hyprland env vars
  else
    info "No Nvidia GPU detected, skipping Nvidia setup"
  fi
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
