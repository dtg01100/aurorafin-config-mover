#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
    LIB_DIR="$SCRIPT_DIR/lib"
else
    LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
fi

source "$LIB_DIR/common.sh"
source "$LIB_DIR/detect.sh"
source "$LIB_DIR/archive.sh"
source "$LIB_DIR/preflight.sh"
source "$LIB_DIR/flatpaks.sh"

show_post_help() {
    cat << EOF
${BOLD}Bluefin-Aurora Migration - Post-Rebase Phase${RESET}

${BOLD}USAGE${RESET}
    $(basename "$0") [OPTIONS]

${BOLD}DESCRIPTION${RESET}
    Complete migration after rebasing between Bluefin and Aurora.
    This script should be run AFTER the rebase and reboot.

${BOLD}OPTIONS${RESET}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -y, --yes               Skip all confirmations
    --dry-run               Show what would happen without making changes
    --restore <dir>         Restore from a backup directory
    --skip-systemd-sysusers Skip running systemd-sysusers
    --skip-flatpaks         Skip flatpak swap prompts

${BOLD}WHAT THIS SCRIPT DOES${RESET}
    1. Verify successful rebase
    2. Check and fix display manager user issues
    3. Ensure Flathub is configured
    4. Clean up any remaining conflicting configs
    5. Offer to swap desktop-specific flatpaks
    6. Provide rollback instructions if needed

${BOLD}EXAMPLES${RESET}
    $(basename "$0")                            # Run post-migration
    $(basename "$0") --dry-run                  # Preview actions
    $(basename "$0") --restore ~/config-migration-backup-xxx

EOF
}

RESTORE_DIR=""
SKIP_SYSUSERS=false
SKIP_FLATPAKS=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_post_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -y|--yes)
                YES_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --restore)
                RESTORE_DIR="$2"
                shift 2
                ;;
            --skip-systemd-sysusers)
                SKIP_SYSUSERS=true
                shift
                ;;
            --skip-flatpaks)
                SKIP_FLATPAKS=true
                shift
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
}

detect_previous_de() {
    local metadata_dir
    
    if [[ -n "$RESTORE_DIR" ]]; then
        metadata_dir="$RESTORE_DIR/metadata"
    elif [[ -d "$BACKUP_DIR/metadata" ]]; then
        metadata_dir="$BACKUP_DIR/metadata"
    else
        return 1
    fi
    
    if [[ -f "$metadata_dir/previous-de.txt" ]]; then
        SOURCE_DE=$(cat "$metadata_dir/previous-de.txt")
        SOURCE_FAMILY=$(cat "$metadata_dir/previous-family.txt" 2>/dev/null || echo "")
        return 0
    fi
    
    return 1
}

detect_previous_de_from_configs() {
    if [[ -d "$HOME/.config/gnome-shell" ]] || [[ -d "$HOME/.config/nautilus" ]]; then
        SOURCE_DE="gnome"
        SOURCE_FAMILY="bluefin"
    elif [[ -f "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" ]] || [[ -d "$HOME/.config/kwin" ]]; then
        SOURCE_DE="kde"
        SOURCE_FAMILY="aurora"
    else
        return 1
    fi
    return 0
}

cleanup_remaining_configs() {
    local previous_de="$1"
    
    print_section "Cleaning Up Remaining $previous_de Configs"
    
    local cleanup_paths=()
    
    if [[ "$previous_de" == "gnome" ]]; then
        cleanup_paths=(
            "$HOME/.config/gtk-3.0/settings.ini"
            "$HOME/.config/gtk-4.0/settings.ini"
            "$HOME/.gtkrc-2.0"
        )
    elif [[ "$previous_de" == "kde" ]]; then
        cleanup_paths=(
            "$HOME/.config/gtk-3.0"
            "$HOME/.config/gtk-4.0"
            "$HOME/.gtkrc-2.0"
            "$HOME/.config/gtkrc"
            "$HOME/.config/gtkrc-2.0"
        )
    fi
    
    local cleaned=0
    for path in "${cleanup_paths[@]}"; do
        if [[ -e "$path" ]]; then
            if [[ -n "${BACKUP_DIR:-}" ]]; then
                archive_path "$path" "$BACKUP_DIR/configs/cleanup"
            fi
            remove_path "$path"
            ((cleaned++)) || true
        fi
    done
    
    if [[ $cleaned -gt 0 ]]; then
        print_success "Cleaned $cleaned conflicting config paths"
    else
        print_success "No conflicting configs to clean"
    fi
}

print_summary() {
    print_header "MIGRATION COMPLETE"
    
    echo ""
    echo -e "${BOLD}Summary:${RESET}"
    echo ""
    echo "  Previous Desktop: ${SOURCE_DE^^}"
    echo "  Current Desktop:  ${TARGET_DE^^}"
    echo ""
    
    echo -e "${BOLD}Preserved:${RESET}"
    echo "  ✓ Flatpak applications and data"
    echo "  ✓ Homebrew installation"
    echo "  ✓ Distrobox containers"
    echo "  ✓ Shell configurations"
    echo "  ✓ SSH keys"
    echo "  ✓ Git configuration"
    echo ""
    
    if [[ -n "${BACKUP_DIR:-}" ]]; then
        echo -e "${BOLD}Backup Location:${RESET}"
        echo "  $BACKUP_DIR"
        echo ""
        echo -e "${BOLD}Rollback:${RESET}"
        echo "  $BACKUP_DIR/rollback.sh"
        echo ""
    fi
    
    echo -e "${GREEN}Your system is ready to use!${RESET}"
    echo ""
    echo "  Tip: You may want to:"
    echo "    - Customize your new desktop environment"
    echo "    - Review and install additional themes"
    echo "    - Configure keyboard shortcuts"
    echo ""
    
    # Optional settings migration notification
    if [[ -n "${BACKUP_DIR:-}" ]] && [[ -f "$BACKUP_DIR/migrate-settings.sh" ]]; then
        local display_path="${BACKUP_DIR/#$HOME\//\~}/migrate-settings.sh"
        echo ""
        echo -e "${YELLOW}┌─────────────────────────────────────────────────────────────────┐${RESET}"
        echo -e "${YELLOW}│${RESET} ${BOLD}⚠️  OPTIONAL: Settings Migration${RESET}                                "
        echo -e "${YELLOW}│${RESET}                                                                 "
        echo -e "${YELLOW}│${RESET} An experimental settings migration script is available:         "
        echo -e "${YELLOW}│${RESET}                                                                 "
        echo -e "${YELLOW}│${RESET} This can migrate: fonts, wallpaper, themes, icons, and more.   "
        echo -e "${YELLOW}│${RESET}                                                                 "
        echo -e "${YELLOW}│${RESET} ${RED}⚠️  WARNING:${RESET} This feature is ${BOLD}EXPERIMENTAL${RESET} and may not work     "
        echo -e "${YELLOW}│${RESET}     correctly in all cases. Some settings may not transfer      "
        echo -e "${YELLOW}│${RESET}     properly between GNOME and KDE.                             "
        echo -e "${YELLOW}│${RESET}                                                                 "
        echo -e "${YELLOW}│${RESET} Recommended: Run with ${BOLD}--dry-run${RESET} first to preview changes.       "
        echo -e "${YELLOW}└─────────────────────────────────────────────────────────────────┘${RESET}"
        echo ""
        echo -e "  ${BOLD}Script location:${RESET} $display_path"
    fi
}

do_restore() {
    local restore_dir="$1"
    
    print_header "RESTORING CONFIGURATION"
    
    if [[ ! -d "$restore_dir" ]]; then
        error "Restore directory not found: $restore_dir"
    fi
    
    local restore_script="$restore_dir/restore-configs.sh"
    
    if [[ -f "$restore_script" ]]; then
        info "Running restore script: $restore_script"
        "$restore_script"
    else
        warn "No restore script found at: $restore_script"
        
        if [[ -d "$restore_dir/configs" ]]; then
            info "Manually restoring from: $restore_dir/configs"
            
            for config_dir in "$restore_dir/configs"/*; do
                [[ -d "$config_dir" ]] || continue
                
                while IFS= read -r -d '' archived_path; do
                    local rel_path="${archived_path#"$config_dir"/}"
                    local dest_path="$HOME/$rel_path"
                    local dest_parent
                    dest_parent=$(dirname "$dest_path")
                    
                    if [[ ! -e "$dest_path" ]]; then
                        mkdir -p "$dest_parent"
                        cp -a "$archived_path" "$dest_path"
                        info "Restored: $dest_path"
                    else
                        warn "Skipping (exists): $dest_path"
                    fi
                done < <(find "$config_dir" -type f -print0 2>/dev/null)
            done
        fi
    fi
    
    print_success "Restore complete"
}

main() {
    parse_args "$@"
    
    print_header "BLUEFIN ↔ AURORA MIGRATION TOOL"
    echo "                      Post-Rebase Phase"
    
    check_dependencies
    
    display_unsupported_warning
    
    if [[ -n "$RESTORE_DIR" ]]; then
        do_restore "$RESTORE_DIR"
        exit 0
    fi
    
    info "Detecting current system..."
    detect_current_image
    
    TARGET_DE="$SOURCE_DE"
    TARGET_FAMILY="$SOURCE_FAMILY"
    
    if ! detect_previous_de && ! detect_previous_de_from_configs; then
        warn "Could not determine previous desktop environment"
        warn "Assuming migration from opposite desktop"
        
        case "$TARGET_DE" in
            gnome) SOURCE_DE="kde"; SOURCE_FAMILY="aurora" ;;
            kde)   SOURCE_DE="gnome"; SOURCE_FAMILY="bluefin" ;;
        esac
    fi
    
    print_section "Migration Direction"
    echo ""
    echo "  Previous: ${SOURCE_FAMILY} (${SOURCE_DE})"
    echo "  Current:  ${SOURCE_FAMILY} (${TARGET_DE})"
    
    if [[ "$SOURCE_DE" == "$TARGET_DE" ]]; then
        print_warning "Source and target desktop are the same."
        echo "  This may indicate the script is being run on the wrong system."
        echo ""
        
        if ! confirm "Continue anyway?" "n"; then
            exit 0
        fi
    fi
    
    echo ""
    if ! confirm "Proceed with post-migration cleanup?" "n"; then
        echo "Migration cancelled."
        exit 0
    fi
    
    if [[ "$SKIP_SYSUSERS" != "true" ]]; then
        run_post_rebase_system_checks "$TARGET_DE" || true
    fi
    
    cleanup_remaining_configs "$SOURCE_DE"
    
    if [[ "$SKIP_FLATPAKS" != "true" ]]; then
        run_flatpak_management "$SOURCE_DE" "$TARGET_DE"
    fi
    
    print_summary
}

main "$@"
