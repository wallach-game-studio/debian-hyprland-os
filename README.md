# debian-hyprland-os

Automated Hyprland desktop environment installer for **Debian 12 (Bookworm)** and **Ubuntu 24.04 LTS (Noble)**.

## Quick Start

```bash
sudo bash install.sh
```

Or for CI/automation:

```bash
sudo bash install.sh --non-interactive --skip-nvidia
```

## Features

### Phase 1 — Core Desktop
- **Hyprland** — Dynamic tiling Wayland compositor with animations & blur (installed as a prebuilt package via [Nix](https://nixos.org/), since neither distro ships a libwayland new enough for current Hyprland releases)
- **Waybar** — Customizable status bar with workspaces, system tray, media controls
- **Rofi** — Application launcher with drun/run/window modes
- **Dunst** — Notification daemon with urgency-based theming
- **Alacritty** — GPU-accelerated terminal with Catppuccin Mocha theme
- **Thunar** — Lightweight file manager
- **PipeWire/WirePlumber** — Modern audio system
- **Swaylock/Swayidle** — Screen locking and idle management
- **Grim/Slurp** — Screenshot tools
- **Nvidia** — Optional proprietary driver support with Hyprland env configuration

### Phase 2 — Planned
- Wayland/X11 session switching
- Drag-and-drop application launcher

## Usage

```bash
sudo bash install.sh [options]

Options:
  --non-interactive   Skip prompts (for CI)
  --skip-nvidia       Skip Nvidia GPU detection and driver install
```

## Configuration

All configs live in `configs/` and are copied to `~/.config/` during install:

| Component  | Config Path                     |
|------------|---------------------------------|
| Hyprland   | `configs/hyprland/hyprland.conf` |
| Waybar     | `configs/waybar/`                |
| Rofi       | `configs/rofi/config.rasi`       |
| Dunst      | `configs/dunst/dunstrc`          |
| Alacritty  | `configs/alacritty/alacritty.toml` |

Edit any file before installation to customize.

## Keybindings

| Key                           | Action                        |
|-------------------------------|-------------------------------|
| `SUPER + Return`              | Open terminal                 |
| `SUPER + Space`               | Application launcher          |
| `SUPER + Q`                   | Close window                  |
| `SUPER + F`                   | Fullscreen                    |
| `SUPER + Shift + F`           | Toggle floating               |
| `SUPER + Shift + S`           | Screenshot (region)           |
| `SUPER + 1-0`                 | Switch workspace              |
| `SUPER + Shift + 1-0`         | Move window to workspace      |
| `SUPER + L`                   | Lock screen                   |
| `Print`                       | Full screenshot               |
| `Shift + Print`               | Region screenshot             |

## Testing

Installation is automatically tested via KVM on every push:

- **Debian 12** cloud image
- **Ubuntu 24.04** cloud image

See `.github/workflows/test-installation.yml` and `scripts/kvm/` for details.

### Local KVM Testing

```bash
# Prerequisites
sudo apt install qemu-system-x86 qemu-utils cloud-image-utils genisoimage sshpass

# Download a cloud image
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2

# Run the test pipeline
bash scripts/kvm/provision-vm.sh debian12 /path/to/debian-12-genericcloud-amd64.qcow2
bash scripts/kvm/wait-for-ssh.sh 127.0.0.1 2222 120
bash scripts/kvm/run-install-test.sh debian12
bash scripts/kvm/verify-desktop.sh debian12
bash scripts/kvm/capture-screenshot.sh debian12
bash scripts/kvm/collect-metrics.sh debian12
bash scripts/kvm/teardown-vm.sh debian12
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for a full local development guide,
including manual VNC desktop sessions and previewing the GitHub Pages site.

## Project Structure

```
.
├── install.sh              # Main installer script
├── configs/                # Default configuration files
│   ├── hyprland/
│   ├── waybar/
│   ├── rofi/
│   ├── dunst/
│   └── alacritty/
├── scripts/kvm/            # KVM test automation
├── .github/workflows/      # CI pipeline
└── test-results/           # CI test artifacts
```

## License

MIT
