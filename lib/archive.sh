#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

GNOME_PATHS_FILE="$SCRIPT_DIR/../configs/gnome-paths.txt"
KDE_PATHS_FILE="$SCRIPT_DIR/../configs/kde-paths.txt"

load_config_paths() {
    local de="$1"
    local paths_file
    
    case "$de" in
        gnome) paths_file="$GNOME_PATHS_FILE" ;;
        kde)   paths_file="$KDE_PATHS_FILE" ;;
        *)     return 1 ;;
    esac
    
    if [[ ! -f "$paths_file" ]]; then
        warn "Config paths file not found: $paths_file"
        return 1
    fi
    
    local paths=()
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        paths+=("$HOME/$line")
    done < "$paths_file"
    
    printf '%s\n' "${paths[@]}"
}

archive_de_configs() {
    local de="$1"
    local dest_dir="$2"
    
    print_section "Archiving $de Configuration Files"
    
    local config_dir="$dest_dir/configs/$de"
    run_cmd "mkdir -p '$config_dir'"
    
    local count=0
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        
        if [[ -e "$path" ]]; then
            archive_path "$path" "$config_dir"
            ((count++)) || true
        fi
    done < <(load_config_paths "$de")
    
    if [[ $count -eq 0 ]]; then
        warn "No $de configuration files found to archive"
    else
        print_success "Archived $count $de configuration paths"
    fi
}

archive_all_configs() {
    local de="$1"
    local backup_dir="$2"
    
    archive_de_configs "$de" "$backup_dir"
}

get_preserved_paths() {
    cat << 'EOF'
.var/app
.local/share/flatpak
.local/share/containers
.distrobox
.homebrew
.ssh
.gitconfig
.gitignore_global
.bashrc
.bash_profile
.zshrc
.zprofile
.profile
.mozilla
.config/libreoffice
.config/Code
.config/VSCode
.local/share/fonts
.local/share/fonts
.config/fontconfig
EOF
}

check_preserved_path() {
    local path="$1"
    local preserved
    preserved=$(get_preserved_paths)
    
    while IFS= read -r preserved_path; do
        [[ -z "$preserved_path" ]] && continue
        if [[ "$path" == *"$preserved_path"* ]] || [[ "$preserved_path" == *"$path"* ]]; then
            return 0
        fi
    done <<< "$preserved"
    
    return 1
}

reset_gtk_configs() {
    local action="${1:-archive}"
    local backup_dir="${2:-}"
    
    print_section "Resetting GTK Configuration Files"
    
    local gtk_paths=(
        "$HOME/.config/gtk-3.0/settings.ini"
        "$HOME/.config/gtk-4.0/settings.ini"
        "$HOME/.gtkrc-2.0"
    )
    
    for path in "${gtk_paths[@]}"; do
        if [[ -e "$path" ]]; then
            if [[ "$action" == "archive" && -n "$backup_dir" ]]; then
                archive_path "$path" "$backup_dir/configs/gtk"
            fi
            remove_path "$path"
        fi
    done
    
    print_success "GTK configs reset"
}

reset_icon_theme() {
    local target_de="$1"
    
    print_section "Resetting Icon Theme"
    
    local icons_config="$HOME/.local/share/icons/default/index.theme"
    
    if [[ -e "$icons_config" ]]; then
        archive_path "$icons_config" "$BACKUP_DIR/configs/icons"
        remove_path "$icons_config"
    fi
    
    case "$target_de" in
        gnome)
            info "GNOME will use Adwaita icons by default"
            ;;
        kde)
            info "KDE will use Breeze icons by default"
            ;;
    esac
    
    print_success "Icon theme reset"
}

generate_rollback_script() {
    local backup_dir="$1"
    local source_image="$2"
    local rollback_script="$backup_dir/rollback.sh"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} Would create rollback script: $rollback_script"
        return 0
    fi
    
    cat > "$rollback_script" << 'ROLLBACK_SCRIPT'
#!/bin/bash
set -euo pipefail

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

ROLLBACK_SCRIPT

    cat >> "$rollback_script" << ROLLBACK_SCRIPT
PREVIOUS_IMAGE="$source_image"
PREVIOUS_DE="$SOURCE_DE"
TIMESTAMP="$(date -Iseconds)"

echo ""
echo -e "\${CYAN}════════════════════════════════════════════════════════════════\${RESET}"
echo -e "\${CYAN}║\${RESET}\${BOLD}      MIGRATION ROLLBACK SCRIPT                               \${RESET}\${CYAN}║\${RESET}"
echo -e "\${CYAN}════════════════════════════════════════════════════════════════\${RESET}"
echo ""
echo -e "  \${BOLD}Previous Image:\${RESET} \$PREVIOUS_IMAGE"
echo -e "  \${BOLD}Backup Dir:\${RESET}    \$BACKUP_DIR"
echo -e "  \${BOLD}Created:\${RESET}       \$TIMESTAMP"
echo ""

if [[ "\${1:-}" != "-y" && "\${1:-}" != "--yes" ]]; then
    echo -e "\${YELLOW}This script will:\${RESET}"
    echo "  1. Show commands to rebase back to the previous image"
    echo "  2. Restore archived configuration files"
    echo ""
    read -rp "Proceed with rollback? [y/N]: " confirm
    if [[ "\$confirm" != "y" && "\$confirm" != "Y" ]]; then
        echo "Rollback cancelled."
        exit 0
    fi
fi

echo ""
echo -e "\${BOLD}═════════════════════════════════════════════════════════════════\${RESET}"
echo -e "\${BOLD}STEP 1: REBASE BACK\${RESET}"
echo -e "\${BOLD}═════════════════════════════════════════════════════════════════\${RESET}"
echo ""
echo "Run these commands to rebase back to your previous image:"
echo ""
echo -e "  \${CYAN}sudo bootc switch \$PREVIOUS_IMAGE\${RESET}"
echo -e "  \${CYAN}sudo bootc switch --enforce-container-sigpolicy \$PREVIOUS_IMAGE\${RESET}"
echo -e "  \${CYAN}sudo reboot\${RESET}"
echo ""
echo "After reboot, restore your configs with:"
echo -e "  \${CYAN}\$BACKUP_DIR/restore-configs.sh\${RESET}"
echo ""
ROLLBACK_SCRIPT

    chmod +x "$rollback_script"
    info "Rollback script created: $rollback_script"
}

generate_restore_script() {
    local backup_dir="$1"
    local restore_script="$backup_dir/restore-configs.sh"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} Would create restore script: $restore_script"
        return 0
    fi
    
    cat > "$restore_script" << 'RESTORE_SCRIPT'
#!/bin/bash
set -euo pipefail

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

RESTORE_SCRIPT

    cat >> "$restore_script" << RESTORE_SCRIPT
echo ""
echo -e "\${BOLD}Restoring Configuration Files\${RESET}"
echo ""

for config_dir in "\$BACKUP_DIR/configs"/*; do
    [[ -d "\$config_dir" ]] || continue
    
    de_name=\$(basename "\$config_dir")
    echo -e "\${YELLOW}Restoring \$de_name configs...\${RESET}"
    
    while IFS= read -r -d '' archived_path; do
        rel_path="\${archived_path#"\$config_dir/"}"
        dest_path="\$HOME/\$rel_path"
        
        if [[ -e "\$dest_path" ]]; then
            echo "  Skipping (exists): \$dest_path"
        else
            dest_parent=\$(dirname "\$dest_path")
            mkdir -p "\$dest_parent"
            cp -a "\$archived_path" "\$dest_path"
            echo "  Restored: \$dest_path"
        fi
    done < <(find "\$config_dir" -type f -print0 2>/dev/null)
done

echo ""
echo -e "\${GREEN}✓ Configuration restore complete\${RESET}"
echo ""
RESTORE_SCRIPT

    chmod +x "$restore_script"
    info "Restore script created: $restore_script"
}

copy_post_migrate_script() {
    local backup_dir="$1"
    local script_dir
    script_dir=$(get_script_dir)
    local post_script="$script_dir/../migrate-post.sh"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} Would copy post-migration script to: $backup_dir/migrate-post.sh"
        return 0
    fi
    
    if [[ -f "$post_script" ]]; then
        cp "$post_script" "$backup_dir/migrate-post.sh"
        chmod +x "$backup_dir/migrate-post.sh"
        info "Post-migration script copied to: $backup_dir/migrate-post.sh"
    fi
}

write_migration_metadata() {
    local backup_dir="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} Would write metadata to: $backup_dir/metadata/"
        return 0
    fi
    
    echo "$SOURCE_FAMILY" > "$backup_dir/metadata/previous-family.txt"
    echo "$SOURCE_DE" > "$backup_dir/metadata/previous-de.txt"
    echo "$SOURCE_IMAGE" > "$backup_dir/metadata/previous-image.txt"
    echo "$SOURCE_VARIANT" > "$backup_dir/metadata/previous-variant.txt"
    echo "$SOURCE_TAG" > "$backup_dir/metadata/previous-tag.txt"
    echo "$TARGET_FAMILY" > "$backup_dir/metadata/target-family.txt"
    echo "$TARGET_DE" > "$backup_dir/metadata/target-de.txt"
    echo "$TARGET_IMAGE" > "$backup_dir/metadata/target-image.txt"
    date -Iseconds > "$backup_dir/metadata/timestamp.txt"
}
