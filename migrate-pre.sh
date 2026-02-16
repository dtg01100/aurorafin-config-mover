#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/common.sh"
source "$LIB_DIR/detect.sh"
source "$LIB_DIR/archive.sh"
source "$LIB_DIR/preflight.sh"

show_pre_help() {
    cat << EOF
${BOLD}Bluefin-Aurora Migration - Pre-Rebase Phase${RESET}

${BOLD}USAGE${RESET}
    $(basename "$0") [OPTIONS]

${BOLD}DESCRIPTION${RESET}
    Prepare for migration between Bluefin (GNOME) and Aurora (KDE).
    This script should be run BEFORE the rebase.

${BOLD}OPTIONS${RESET}
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -y, --yes           Skip all confirmations
    --dry-run           Show what would happen without making changes
    --target <image>    Specify target image directly (skip menu)

${BOLD}WHAT THIS SCRIPT DOES${RESET}
    1. Detect current Bluefin/Aurora image
    2. Offer matching target images for migration
    3. Run preflight system checks
    4. Archive desktop-specific configuration files
    5. Generate rollback scripts
    6. Print rebase commands to execute

${BOLD}EXAMPLES${RESET}
    $(basename "$0")                    # Interactive migration
    $(basename "$0") --dry-run          # Preview what would happen
    $(basename "$0") -y                 # Run without prompts
    $(basename "$0") --target aurora-dx:stable

${BOLD}AFTER RUNNING THIS SCRIPT${RESET}
    1. Execute the printed bootc switch commands
    2. Reboot
    3. Run the post-migration script from the backup directory

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_pre_help
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
            --target)
                TARGET_IMAGE="$2"
                shift 2
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
}

print_rebase_commands() {
    print_section "REBASE COMMANDS"
    
    echo ""
    echo -e "${BOLD}Step 1: Initial rebase${RESET}"
    echo -e "  ${CYAN}sudo bootc switch $TARGET_IMAGE${RESET}"
    echo ""
    echo -e "${BOLD}Step 2: Verify signed image (after step 1 completes)${RESET}"
    echo -e "  ${CYAN}sudo bootc switch --enforce-container-sigpolicy \\${RESET}"
    echo -e "    ${CYAN}$TARGET_IMAGE${RESET}"
    echo ""
    echo -e "${BOLD}Step 3: Reboot${RESET}"
    echo -e "  ${CYAN}sudo reboot${RESET}"
    echo ""
    echo -e "${BOLD}Step 4: After reboot, run the post-migration script${RESET}"
    local display_path="${BACKUP_DIR/#$HOME\//\~}/migrate-post.sh"
    echo -e "  ${CYAN}$display_path${RESET}"
    echo ""
}

main() {
    parse_args "$@"
    
    print_header "BLUEFIN ↔ AURORA MIGRATION TOOL"
    echo "                      Pre-Rebase Phase"
    
    check_dependencies
    
    display_unsupported_warning
    
    info "Detecting current system..."
    detect_current_image
    
    if [[ -n "${TARGET_IMAGE:-}" ]]; then
        parse_target_image
    else
        display_image_menu
    fi
    
    print_migration_summary
    
    echo ""
    if ! confirm "Proceed with migration preparation?" "n"; then
        echo "Migration cancelled."
        exit 0
    fi
    
    run_preflight_checks "$TARGET_DE" || true
    
    BACKUP_DIR=$(create_backup_dir "config-migration-backup")
    
    if [[ "$DRY_RUN" != "true" ]]; then
        mkdir -p "$BACKUP_DIR/metadata"
        
        write_manifest
        write_migration_metadata "$BACKUP_DIR"
    fi
    
    archive_all_configs "$SOURCE_DE" "$BACKUP_DIR"
    
    reset_gtk_configs "archive" "$BACKUP_DIR"
    reset_icon_theme "$TARGET_DE"
    
    generate_rollback_script "$BACKUP_DIR" "$SOURCE_IMAGE"
    generate_restore_script "$BACKUP_DIR"
    copy_post_migrate_script "$BACKUP_DIR"
    
    print_section "BACKUP LOCATION"
    echo ""
    echo -e "  ${BOLD}$BACKUP_DIR${RESET}"
    echo ""
    echo "  Contains:"
    echo "    - rollback.sh         (undo the migration)"
    echo "    - restore-configs.sh  (restore archived configs)"
    echo "    - migrate-post.sh     (run after reboot)"
    echo "    - manifest.json       (migration details)"
    echo "    - configs/            (archived DE configs)"
    echo ""
    
    print_rebase_commands
    
    print_header "NEXT STEPS"
    echo ""
    echo "  1. Run the rebase commands above"
    echo "  2. Reboot into your new system"
    echo "  3. Run: $BACKUP_DIR/migrate-post.sh"
    echo ""
    echo -e "${YELLOW}If something goes wrong, you can rollback using:${RESET}"
    echo -e "  $BACKUP_DIR/rollback.sh"
    echo ""
}

main "$@"
