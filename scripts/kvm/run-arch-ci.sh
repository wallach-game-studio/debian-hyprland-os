#!/usr/bin/env bash
# scripts/kvm/run-arch-ci.sh
#
# Run the full KVM CI flow on an Arch Linux host.
# 1. Detect that the host is Arch.
# 2. Install host prerequisites (qemu, virt-manager, virt-viewer, genisoimage, curl).
# 3. Download a Debian 12 cloud image (cached locally).
# 4. Provision the VM with the existing kvm scripts.
# 5. Run the install test inside the VM.
# 6. Start a VNC session for manual desktop preview.
# 7. Tear down the VM.
#
# Usage: ./scripts/kvm/run-arch-ci.sh

set -euo pipefail

# --------------------------------------------------------------------
# Helper: check that we are on Arch Linux
# --------------------------------------------------------------------
check_arch() {
  if ! grep -q '^ID=arch$' /etc/os-release; then
    echo 'Error: This script must be run on an Arch Linux host.' >&2
    exit 1
  fi
}

# --------------------------------------------------------------------
# Install host prerequisites using pacman
# --------------------------------------------------------------------
install_host_pkgs() {
  echo '==> Installing host packages (qemu, virt-manager, virt-viewer, genisoimage, curl)'
  # Use --noconfirm to avoid interactive prompt
  sudo pacman -S --noconfirm qemu virt-manager virt-viewer genisoimage curl
}

# --------------------------------------------------------------------
# Download Debian 12 cloud image (qcow2), cached in $HOME/debiancloud
# --------------------------------------------------------------------
get_debian_image() {
  local base_dir="${HOME}/debiancloud"
  local img_name="debian-12-genericcloud-amd64-20240612.qcow2"
  local img_path="${base_dir}/${img_name}"

  mkdir -p "$base_dir"

  if [[ ! -f "$img_path" ]]; then
    echo '==> Downloading Debian 12 cloud image...'
    curl -L https://cdimage.debian.org/cloud/bookworm/current/debian-12-genericcloud-amd64-20240612.qcow2 -o "$img_path"
  else
    echo '==> Using cached Debian 12 cloud image:'
    echo "  $img_path"
  fi

  echo "$img_path"
}

# --------------------------------------------------------------------
# Main CI flow
# --------------------------------------------------------------------
main() {
  check_arch
  install_host_pkgs || { echo 'Failed to install host packages'; exit 1; }

  local distro="debian12"
  local debian_image

  debian_image=$(get_debian_image)

  echo '==> Provisioning VM...'
  ./scripts/kvm/provision-vm.sh "$distro" "$debian_image"

  echo '==> Running install test...'
  ./scripts/kvm/run-install-test.sh "$distro"

  echo '==> Starting manual desktop (VNC)...'
  ./scripts/kvm/start-manual-desktop.sh "$distro"

  echo '==> Teardown VM...'
  ./scripts/kvm/  teardown-vm.sh "$distro"
  # Clean up temporary data to avoid clutter
  rm -rf "/tmp/kvm-test/${distro}"
}


main "$@"
