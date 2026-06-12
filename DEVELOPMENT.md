# Local Development Guide

This is a manual for working on `debian-hyprland-os` outside of CI: editing
configs, testing `install.sh` end-to-end in a disposable VM, and previewing
the GitHub Pages site.

## Project layout

```
.
├── install.sh              # Main installer script
├── configs/                # Default configuration files (copied to ~/.config)
│   ├── hyprland/
│   ├── waybar/
│   ├── rofi/
│   ├── dunst/
│   └── alacritty/
├── docs/                    # GitHub Pages site (docs/index.html)
├── scripts/kvm/             # KVM test automation (see below)
├── tests/                   # Unit/script tests
├── .github/workflows/       # CI pipelines
└── test-results/            # CI test artifacts
```

Editing a file under `configs/` and re-running `install.sh` is the normal
loop — the installer copies these into `~/.config/` on the target machine.

## Testing in a KVM VM

`scripts/kvm/` provisions a throwaway VM from a cloud image, runs
`install.sh` inside it, verifies the result, and tears it down again. This
is exactly what CI runs (`.github/workflows/test-installation.yml`), so it's
the most reliable way to reproduce a CI failure locally.

### Prerequisites

```bash
sudo apt install qemu-system-x86 qemu-utils cloud-image-utils genisoimage \
                 openssh-client sshpass
pip install --user vncdotool   # only needed for capture-screenshot.sh
```

KVM acceleration (`/dev/kvm`) needs to be available — check with
`ls /dev/kvm`. Without it, `qemu-system-x86_64 -enable-kvm` will fail.

### 1. Download a cloud image

```bash
# Debian 12
wget -O debian12.qcow2 \
  https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2

# Ubuntu 24.04
wget -O ubuntu2404.img \
  https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
```

### 2. Provision and boot the VM

```bash
bash scripts/kvm/provision-vm.sh debian12 /path/to/debian12.qcow2
```

This creates a qcow2 overlay + cloud-init ISO under `/tmp/kvm-test/<distro>/`,
generates a per-VM SSH key (`vm_key`), and boots the VM with:

- SSH forwarded to `127.0.0.1:2222` (user `tester`, passwordless sudo)
- VNC on `127.0.0.1:5900`

### 3. Wait for SSH / cloud-init

```bash
bash scripts/kvm/wait-for-ssh.sh 127.0.0.1 2222 180 debian12
```

### 4. Run the installer in the VM

Copies the working tree into the VM and runs `install.sh --non-interactive`,
capturing logs to `test-results/debian12/`:

```bash
bash scripts/kvm/run-install-test.sh debian12
```

Iterating on a config change is usually faster done directly over SSH instead
of re-running the whole installer:

```bash
ssh -i /tmp/kvm-test/debian12/vm_key -p 2222 tester@127.0.0.1
```

### 5. Verify the desktop environment

Starts Hyprland headlessly inside the VM and checks that the expected
binaries/configs are present:

```bash
bash scripts/kvm/verify-desktop.sh debian12
```

### 6. Manual desktop session over VNC

To actually look at the desktop (not just headless checks), restart the
console session so Hyprland starts on tty1, then connect a VNC viewer:

```bash
bash scripts/kvm/start-manual-desktop.sh debian12

# In another terminal — any VNC client works, e.g.:
vncviewer 127.0.0.1:5900
# or: remmina -c vnc://127.0.0.1:5900
```

If the VM has no GPU (`/dev/dri`), Hyprland won't auto-start — `.profile`
prints an explanatory message on the console instead of crash-looping. This
is expected for software-only VMs; CI's GitHub-hosted runners do expose a
virtio GPU.

### 7. Screenshots & metrics

```bash
bash scripts/kvm/capture-screenshot.sh debian12   # -> test-results/debian12/*.png
bash scripts/kvm/collect-metrics.sh debian12      # -> test-results/debian12/metrics.json
```

### 8. Tear down

```bash
bash scripts/kvm/teardown-vm.sh debian12
```

This shuts down the VM, kills the QEMU process if needed, and removes
`/tmp/kvm-test/debian12/`.

## Running the test suite

Quick structural/syntax checks that need no root access or KVM:

```bash
bash tests/ci-validate.sh
```

## Previewing the GitHub Pages site

`docs/index.html` is a static, single-file page (no build step). Preview it
with any local web server:

```bash
cd docs && python3 -m http.server 8000
# then open http://localhost:8000
```

Opening `docs/index.html` directly via `file://` also works since it has no
external dependencies besides Google Fonts.

## CI reference

- **`.github/workflows/test-installation.yml`** — runs the full KVM pipeline
  above for Debian 12 and Ubuntu 24.04 on every push/PR. Manually triggering
  it via `workflow_dispatch` lets you set `manual_test_minutes` to keep the
  VM alive and exposes a noVNC session over a temporary public URL for
  browser-based manual testing.
- **`.github/workflows/pages.yml`** — builds and deploys `docs/` to GitHub
  Pages on pushes to `main` that touch `docs/**`.
