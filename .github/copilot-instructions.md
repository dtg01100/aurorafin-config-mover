# Copilot Instructions

This is a migration tool for switching between Bluefin (GNOME) and Aurora (KDE) desktop environments on Universal Blue systems.

## Project Structure

```
├── lib/
│   ├── common.sh       # Shared functions, logging, colors
│   ├── detect.sh       # Image/DE detection via bootc
│   ├── archive.sh      # Backup and rollback scripts
│   ├── preflight.sh    # System checks before/after rebase
│   └── flatpaks.sh     # Flatpak swap from upstream Brewfiles
├── configs/
│   ├── gnome-paths.txt # GNOME config paths to archive
│   └── kde-paths.txt   # KDE config paths to archive
├── migrate-pre.sh      # Run before rebase
├── migrate-post.sh     # Run after rebase and reboot
└── scripts/
    ├── check-urls.sh   # Verify Brewfile URLs are accessible
    └── sync-flatpaks.sh # Sync and diff flatpak lists
```

## Key Files

### `lib/flatpaks.sh`

Contains the URLs for fetching flatpak Brewfiles:
- `BLUEFIN_BREWFILE_URL` - URL to Bluefin's system-flatpaks.Brewfile
- `AURORA_BREWFILE_URL` - URL to Aurora's system-flatpaks.Brewfile

These URLs may change when upstream repositories reorganize. If a URL fails:
1. Check https://github.com/projectbluefin/common for Bluefin
2. Check https://github.com/get-aurora-dev/common for Aurora
3. Look in `system_files/*/usr/share/ublue-os/homebrew/` directories
4. Update the URL in `lib/flatpaks.sh`

### Config Path Files

- `configs/gnome-paths.txt` - Paths relative to $HOME to archive when migrating FROM GNOME
- `configs/kde-paths.txt` - Paths relative to $HOME to archive when migrating FROM KDE

## Shell Script Conventions

- Use `set -euo pipefail` at the top of scripts
- Source library files from `$SCRIPT_DIR` or `$LIB_DIR`
- Use functions from `lib/common.sh` for logging:
  - `info()`, `warn()`, `error()`, `debug()`
  - `print_success()`, `print_warning()`, `print_error()`
  - `print_header()`, `print_section()`
  - `confirm()` for user prompts
- Support `--dry-run` mode by checking `$DRY_RUN`

## Testing Changes

When modifying scripts:
1. Run `bash -n <script.sh>` to check syntax
2. Run with `--dry-run` to preview actions without changes
3. Test URL changes by sourcing and calling `get_de_flatpaks "gnome"` or `"kde"`

## Flatpak URL Detection

When fixing Brewfile URL issues:
1. Use the GitHub API to list repository contents
2. Check for files named `system-flatpaks.Brewfile`
3. Verify the URL returns valid content with `flatpak "` entries
4. Update both `BLUEFIN_BREWFILE_URL` and `AURORA_BREWFILE_URL` if needed
