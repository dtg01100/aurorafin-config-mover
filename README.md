# Bluefin-Aurora Migration Tool

A script to handle user configuration migration between Universal Blue's Bluefin (GNOME) and Aurora (KDE) desktop environments.

## Overview

This tool helps you switch between Bluefin and Aurora while:

- Archiving desktop-specific configurations
- Preserving all user data (Flatpaks, Homebrew, Distrobox, etc.)
- Generating rollback scripts for safety
- Checking for common migration issues

## Requirements

- Bluefin or Aurora installation
- `bootc` command available
- `jq` for JSON parsing
- `ostree` for deployment management

## Usage

### Phase 1: Pre-Rebase (Before Switching)

Run this script on your current system **before** the rebase:

```bash
./migrate-pre.sh
```

This will:

1. Detect your current image (Bluefin or Aurora)
2. Display a menu of matching target images
3. Run preflight system checks
4. Archive desktop-specific configuration files
5. Generate rollback and restore scripts
6. Print the exact `bootc switch` commands to run

### Phase 2: Execute the Rebase

Run the commands printed by the pre-rebase script:

```bash
# Step 1: Initial rebase
sudo bootc switch ghcr.io/ublue-os/aurora-dx:stable

# Step 2: Verify signed image
sudo bootc switch --enforce-container-sigpolicy ghcr.io/ublue-os/aurora-dx:stable

# Step 3: Reboot
sudo reboot
```

### Phase 3: Post-Rebase (After First Boot)

After booting into the new system, run the post-migration script:

```bash
~/config-migration-backup-YYYYMMDD-HHMMSS/migrate-post.sh
```

This will:

1. Verify the rebase was successful
2. Check and fix display manager user issues
3. Clean up any remaining conflicting configs
4. Offer to swap desktop-specific flatpaks
5. Ensure Flathub is configured

## Command Line Options

### migrate-pre.sh

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-v, --verbose` | Enable verbose output |
| `-y, --yes` | Skip all confirmations |
| `--dry-run` | Preview actions without making changes |
| `--target <image>` | Specify target image directly (skip menu) |

### migrate-post.sh

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-v, --verbose` | Enable verbose output |
| `-y, --yes` | Skip all confirmations |
| `--dry-run` | Preview actions without making changes |
| `--restore <dir>` | Restore from a backup directory |
| `--skip-systemd-sysusers` | Skip running systemd-sysusers |
| `--skip-flatpaks` | Skip flatpak swap prompts |

## Rollback

If something goes wrong, use the rollback script:

```bash
~/config-migration-backup-YYYYMMDD-HHMMSS/rollback.sh
```

This will print the commands to rebase back to your previous image and restore your configurations.

## What Gets Archived

### From GNOME (Bluefin → Aurora)

- GNOME Shell settings and extensions
- Nautilus, GNOME Terminal, and other GNOME apps
- dconf/GSettings
- GTK theme settings
- GNOME Keyring data
- And more (see `configs/gnome-paths.txt`)

### From KDE (Aurora → Bluefin)

- Plasma desktop settings
- KWin window manager rules
- Dolphin, Konsole, and other KDE apps
- KDE Connect data
- KWallet data
- GTK settings (modified by KDE)
- And more (see `configs/kde-paths.txt`)

## What Gets Preserved

The following are **never modified**:

- `~/.var/app/` - Flatpak application data
- `~/.local/share/flatpak/` - Flatpak installations
- `~/.local/share/containers/` - Podman/Distrobox containers
- `~/.distrobox/` - Distrobox configurations
- `~/.homebrew/` - Homebrew installation
- `~/.ssh/` - SSH keys
- `~/.gitconfig` - Git configuration
- `~/.bashrc`, `~/.zshrc` - Shell configurations
- User documents and media

## Flatpak Swapping

The post-migration script dynamically fetches the official flatpak lists from:

- **Bluefin**: `projectbluefin/common` repository
- **Aurora**: `get-aurora-dev/common` repository

These lists are cached locally for 24 hours to speed up repeated runs.

### How It Works

1. Fetches the `system-flatpaks.Brewfile` from the appropriate repository
2. Parses flatpak IDs from the Brewfile
3. Filters to DE-specific apps only (e.g., `org.gnome.*` or `org.kde.*`)
4. Shared apps like Firefox, Thunderbird, Flatseal are **not affected**

### Bluefin → Aurora (GNOME → KDE)

**Remove:**
- GNOME apps: `org.gnome.Nautilus`, `org.gnome.Terminal`, `org.gnome.TextEditor`, etc.
- GNOME themes: `org.gtk.Gtk3theme.adw-gtk3`

**Install:**
- KDE apps: `org.kde.gwenview`, `org.kde.okular`, `org.kde.kcalc`, etc.
- KDE theme: `org.gtk.Gtk3theme.Breeze`

### Aurora → Bluefin (KDE → GNOME)

**Remove:**
- KDE apps: `org.kde.gwenview`, `org.kde.okular`, `org.kde.kcalc`, etc.
- KDE theme: `org.gtk.Gtk3theme.Breeze`

**Install:**
- GNOME apps: `org.gnome.Nautilus`, `org.gnome.Calculator`, `org.gnome.Calendar`, etc.
- GNOME themes: `org.gtk.Gtk3theme.adw-gtk3`

### Options

You can choose to:
1. **Swap**: Remove old DE flatpaks and install new ones
2. **Install only**: Just install the new DE flatpaks
3. **Remove only**: Just remove old DE flatpaks
4. **Skip**: Don't modify flatpaks

You can also run `ujust install-system-flatpaks` to install the full default set for your new desktop.

## Known Issues

### Display Manager User Missing

In rare cases, the display manager user (`gdm` or `sddm`) may not exist in `/etc/shadow` after rebase. The post-migration script will attempt to fix this with `sudo systemd-sysusers`.

### Layered Packages

If you have layered packages installed via `rpm-ostree install`, these may not persist after rebase. The preflight check will warn you about this.

## Directory Structure

```
bluefin-aurora-migrate/
├── migrate-pre.sh          # Pre-rebase phase script
├── migrate-post.sh         # Post-rebase phase script
├── lib/
│   ├── common.sh           # Shared functions, logging
│   ├── detect.sh           # Image/DE detection
│   ├── archive.sh          # Backup/archiving
│   ├── preflight.sh        # System checks
│   └── flatpaks.sh         # Flatpak swap management
├── configs/
│   ├── gnome-paths.txt     # GNOME config paths
│   └── kde-paths.txt       # KDE config paths
└── README.md
```

## Backup Directory Structure

After running the pre-rebase script, a backup directory is created:

```
~/config-migration-backup-YYYYMMDD-HHMMSS/
├── manifest.json           # Migration details
├── rollback.sh             # Rollback script
├── restore-configs.sh      # Config restore script
├── migrate-post.sh         # Post-migration script
├── logs/
│   └── migration.log       # Detailed log
├── configs/
│   ├── gnome/              # Archived GNOME configs
│   ├── kde/                # Archived KDE configs
│   └── cleanup/            # GTK/icon cleanup
└── metadata/
    ├── previous-de.txt     # Previous desktop
    ├── previous-image.txt  # Previous image ref
    └── timestamp.txt       # When created
```

## Disclaimer

**This script is provided as-is.** While it creates backups and rollback scripts, there is always a risk when modifying system configurations. 

- Test with `--dry-run` first
- Keep the backup directory safe
- Know how to use the rollback script

The Universal Blue project does not officially support rebasing between different desktop environments. Use at your own risk.

## License

MIT License
