#!/usr/bin/env bash
# Provision a KVM VM from a cloud image for Hyprland installation testing
# Usage: provision-vm.sh <distro> <image_path>
set -euo pipefail

DISTRO="${1:?Usage: provision-vm.sh <distro> <image_path>}"
IMAGE_SRC="${2:?Usage: provision-vm.sh <distro> <image_path>}"
WORK_DIR="/tmp/kvm-test/${DISTRO}"
SSH_PORT=2222
VNC_DISPLAY=0

mkdir -p "$WORK_DIR"
mkdir -p "test-results/${DISTRO}"

echo "==> Provisioning VM: ${DISTRO}"
echo "    Source image: ${IMAGE_SRC}"
echo "    Work dir:     ${WORK_DIR}"

# --- Disk image ---
echo "--> Creating overlay disk image (20GB)..."
qemu-img create \
  -f qcow2 \
  -b "$(realpath "$IMAGE_SRC")" \
  -F qcow2 \
  "${WORK_DIR}/disk.img" \
  20G

# --- SSH key ---
echo "--> Generating VM SSH key..."
ssh-keygen -t ed25519 -f "${WORK_DIR}/vm_key" -N "" -q -C "hyprland-test-${DISTRO}"
VM_PUBKEY=$(cat "${WORK_DIR}/vm_key.pub")

# --- cloud-init user-data ---
echo "--> Writing cloud-init config..."
cat > "${WORK_DIR}/user-data" << EOF
#cloud-config
hostname: hyprland-test
fqdn: hyprland-test.local

users:
  - name: tester
    gecos: Hyprland CI Tester
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: tester
    ssh_authorized_keys:
      - ${VM_PUBKEY}

ssh_pwauth: false
disable_root: true

package_update: false
package_upgrade: false

runcmd:
  - touch /tmp/cloud-init-done

final_message: "VM ${DISTRO} ready after \$UPTIME seconds"
EOF

cat > "${WORK_DIR}/meta-data" << EOF
instance-id: hyprland-test-${DISTRO}-$(date +%s)
local-hostname: hyprland-test
EOF

# --- cloud-init ISO ---
echo "--> Creating cloud-init ISO..."
genisoimage \
  -output "${WORK_DIR}/cloud-init.iso" \
  -volid cidata \
  -joliet -rock \
  "${WORK_DIR}/user-data" \
  "${WORK_DIR}/meta-data" \
  2>/dev/null

# --- Launch VM ---
echo "--> Starting KVM VM..."
qemu-system-x86_64 \
  -enable-kvm \
  -machine type=q35,accel=kvm \
  -cpu host \
  -m 4096 \
  -smp cpus=2,sockets=1,cores=2,threads=1 \
  -drive file="${WORK_DIR}/disk.img",format=qcow2,if=virtio,cache=writeback \
  -drive file="${WORK_DIR}/cloud-init.iso",format=raw,if=virtio,readonly=on \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22 \
  -device virtio-vga \
  -vnc 127.0.0.1:${VNC_DISPLAY} \
  -display none \
  -serial file:"${WORK_DIR}/serial.log" \
  -daemonize \
  -pidfile "${WORK_DIR}/vm.pid"

VM_PID=$(cat "${WORK_DIR}/vm.pid")
echo "--> VM started (PID: ${VM_PID})"
echo "--> SSH:  ssh -i ${WORK_DIR}/vm_key -p ${SSH_PORT} tester@127.0.0.1"
echo "--> VNC:  127.0.0.1:590${VNC_DISPLAY}"
echo "==> Provisioning done."
