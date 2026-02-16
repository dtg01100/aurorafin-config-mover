#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
    LIB_DIR="$SCRIPT_DIR/lib"
else
    LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
fi

source "$LIB_DIR/common.sh"

show_settings_help() {
    cat << EOF
${BOLD}Bluefin-Aurora Migration - Settings Migrator${RESET}

${BOLD}${RED}⚠️  EXPERIMENTAL FEATURE${RESET}

    This script is ${BOLD}experimental${RESET} and settings migration between
    desktop environments is inherently fragile. Some settings may not
    transfer correctly or may cause unexpected behavior.

    ${BOLD}Recommendations:${RESET}
    • Always run with ${BOLD}--dry-run${RESET} first to preview changes
    • Back up important data before proceeding
    • Test migrated settings thoroughly after running
    • Be prepared to manually adjust some settings

${BOLD}USAGE${RESET}
    $(basename "$0") [OPTIONS]

${BOLD}DESCRIPTION${RESET}
    Interactive script for migrating settings between Bluefin and Aurora
    desktop environments. Run this AFTER the main migration (post-rebase).

    This script allows you to selectively restore settings from your backup
    that are compatible across desktop environments.

${BOLD}OPTIONS${RESET}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -y, --yes               Skip all confirmations
    --dry-run               Show what would happen without making changes
    --all                   Migrate all compatible settings without prompts
    --backup-dir <dir>      Specify backup directory (default: auto-detect)

${BOLD}SETTINGS THAT CAN BE MIGRATED${RESET}
    • Keychain/Wallet        - GNOME keyring and KWallet credentials
    • GNOME dconf           - Desktop settings (fonts, themes, wallpaper, colors)
    • Font preferences       - Default font selections (KDE, GTK)
    • Wallpaper              - Desktop background images
    • Color schemes          - Desktop color schemes
    • Cursor themes          - Mouse cursor themes
    • Icon themes            - User-custom icon themes (not defaults)
    • GTK themes             - User-custom GTK theme settings

${BOLD}EXAMPLES${RESET}
    $(basename "$0")                            # Interactive mode
    $(basename "$0") --dry-run                  # Preview what would happen
    $(basename "$0") --all                      # Migrate everything
    $(basename "$0") --backup-dir ~/my-backup   # Use specific backup

${BOLD}NOTE${RESET}
    This script focuses on core system/desktop settings that are compatible
    across desktop environments. Browser, editor, terminal, and third-party
    app settings should be migrated manually or are not compatible across DEs.
    SSH/Git configs are already preserved by the main migration scripts.

EOF
}

MIGRATE_ALL=false
BACKUP_DIR=""
SELECTED_SETTINGS=()

# Font migration result tracking
FONT_MIGRATED=0
FONT_SKIPPED=0
FONT_ERRORS=0

declare -A SETTING_CATEGORIES=(
    ["keychain"]="Keychain/Wallet credentials"
    ["dconf"]="GNOME dconf settings (fonts, themes, wallpaper)"
    ["fonts"]="Font preferences (default font selections)"
    ["wallpaper"]="Desktop wallpaper/background"
    ["color-schemes"]="Desktop color schemes"
    ["cursor-themes"]="Mouse cursor themes"
    ["icon-themes"]="Icon themes (user-custom)"
    ["gtk-themes"]="GTK theme settings"
)

declare -A SETTING_PATHS=(
    ["keychain"]=".local/share/keyrings .config/kwallet .local/share/kwallet"
    ["dconf"]=".config/dconf .local/share/dconf"
    ["fonts"]=".config/kdeglobals .config/gtk-3.0 .config/gtk-4.0"
    ["wallpaper"]=".local/share/backgrounds .wallpaper pictures/Wallpapers pictures/Wallpaper"
    ["color-schemes"]=".local/share/color-schemes .color-schemes"
    ["cursor-themes"]=".local/share/icons .icons"
    ["icon-themes"]=".local/share/icons"
    ["gtk-themes"]=".config/gtk-4.0 .config/gtk-3.0 .gtkrc-2.0 .config/gtkrc"
)

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_settings_help
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
            --all)
                MIGRATE_ALL=true
                shift
                ;;
            --backup-dir)
                shift
                if [[ $# -eq 0 ]]; then
                    error "--backup-dir requires a directory argument"
                    exit 1
                fi
                if [[ ! -d "$1" ]]; then
                    error "Directory does not exist: $1"
                    exit 1
                fi
                BACKUP_DIR="$1"
                shift
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
}

detect_backup_dir() {
    if [[ -n "$BACKUP_DIR" ]]; then
        if [[ -d "$BACKUP_DIR" ]]; then
            return 0
        else
            error "Backup directory not found: $BACKUP_DIR"
        fi
    fi

    local search_dirs=(
        "$HOME/config-migration-backup-"*
    )

    local latest_dir=""
    local latest_time=0

    for dir in "${search_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local dir_time
            dir_time=$(stat -c %Y "$dir" 2>/dev/null || echo 0)
            if [[ $dir_time -gt $latest_time ]]; then
                latest_time=$dir_time
                latest_dir="$dir"
            fi
        fi
    done

    if [[ -n "$latest_dir" ]]; then
        BACKUP_DIR="$latest_dir"
        return 0
    fi

    error "No backup directory found. Please run the pre-migration script first."
}

check_ui_availability() {
    if command -v whiptail &>/dev/null; then
        echo "whiptail"
    elif command -v dialog &>/dev/null; then
        echo "dialog"
    else
        echo "none"
    fi
}

show_checkbox_menu() {
    local ui_type="$1"
    local title="$2"
    local message="$3"
    shift 3
    local options=("$@")

    if [[ "$ui_type" == "whiptail" ]]; then
        show_whiptail_checkboxes "$title" "$message" "${options[@]}"
    elif [[ "$ui_type" == "dialog" ]]; then
        show_dialog_checkboxes "$title" "$message" "${options[@]}"
    else
        show_bash_checkboxes "$title" "$message" "${options[@]}"
    fi
}

show_whiptail_checkboxes() {
    local title="$1"
    local message="$2"
    shift 2

    local args=()
    while [[ $# -gt 0 ]]; do
        args+=("$1" "$2" "off")
        shift 2
    done

    whiptail --title "$title" --separate-output --checklist "$message" 20 60 10 "${args[@]}" 2>&1
}

show_dialog_checkboxes() {
    local title="$1"
    local message="$2"
    shift 2

    local args=()
    while [[ $# -gt 0 ]]; do
        args+=("$1" "$2" "off")
        shift 2
    done

    dialog --title "$title" --separate-output --checklist "$message" 20 60 10 "${args[@]}" 2>&1
}

show_bash_checkboxes() {
    local title="$1"
    local message="$2"
    shift 2

    echo ""
    echo -e "${BOLD}$title${RESET}"
    echo ""
    echo -e "$message"
    echo ""

    local options=("$@")
    local num_options=${#options[@]}
    local selected=()

    for ((i=0; i<num_options; i+=2)); do
        local key="${options[$i]}"
        local desc="${options[$((i+1))]}"

        echo -en "  [ ] $key) $desc"
        echo ""
    done

    echo ""
    echo "Enter numbers separated by spaces (e.g., 1 3 5) or 'all' for all: "
    echo -en "> "
    read -r response

    if [[ "$response" == "all" || "$response" == "a" ]]; then
        for ((i=0; i<num_options; i+=2)); do
            selected+=("${options[$i]}")
        done
    else
        # Validate that input is numeric
        if ! [[ "$response" =~ ^[0-9[:space:]]+$ ]]; then
            echo "Invalid input. Please enter numbers only."
            return 1
        fi
        for num in $response; do
            # Skip if not a valid positive integer
            if ! [[ "$num" =~ ^[0-9]+$ ]] || [[ "$num" -lt 1 ]]; then
                continue
            fi
            local idx=$(( (num - 1) * 2 ))
            if [[ $idx -ge 0 && $idx -lt $num_options ]]; then
                selected+=("${options[$idx]}")
            fi
        done
    fi

    printf '%s\n' "${selected[@]}"
}

get_available_settings() {
    local backup_configs="$BACKUP_DIR/configs"
    local available=()

    for category in "${!SETTING_PATHS[@]}"; do
        local paths="${SETTING_PATHS[$category]}"
        local found=false

        # Special handling for dconf - check for user database file
        if [[ "$category" == "dconf" ]]; then
            for path in $paths; do
                local dconf_db="$backup_configs/$path/user"
                if [[ -f "$dconf_db" ]]; then
                    found=true
                    break
                fi
            done
        else
            for path in $paths; do
                local full_path="$backup_configs/$path"
                if [[ -e "$full_path" ]]; then
                    found=true
                    break
                fi
            done
        fi

        if [[ "$found" == "true" ]]; then
            available+=("$category")
        fi
    done

    printf '%s\n' "${available[@]}"
}

get_category_item_count() {
    local category="$1"
    local paths="${SETTING_PATHS[$category]}"
    local count=0

    # Special handling for dconf - check for dconf database files
    if [[ "$category" == "dconf" ]]; then
        for path in $paths; do
            local full_path="$BACKUP_DIR/configs/$path/user"
            if [[ -f "$full_path" ]]; then
                count=$((count + 1))
                debug "Found dconf database: $full_path"
            fi
        done
        echo "$count"
        return
    fi

    for path in $paths; do
        local full_path="$BACKUP_DIR/configs/$path"
        if [[ -e "$full_path" ]]; then
            if [[ -d "$full_path" ]]; then
                count=$((count + $(find "$full_path" -type f 2>/dev/null | wc -l)))
            else
                count=$((count + 1))
            fi
        fi
    done

    echo "$count"
}

build_menu_options() {
    local options=()
    local menu_num=1

    for category in "${!SETTING_CATEGORIES[@]}"; do
        local desc="${SETTING_CATEGORIES[$category]}"
        local item_count
        item_count=$(get_category_item_count "$category")

        if [[ $item_count -gt 0 ]]; then
            options+=("$category" "$desc ($item_count items)")
        else
            options+=("$category" "$desc (not found)")
        fi
        ((menu_num++)) || true
    done

    printf '%s\n' "${options[@]}"
}

# Display experimental warning banner
show_experimental_warning() {
    echo ""
    echo -e "${RED}╔═════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}║${RESET}                                                                     ${RED}║${RESET}"
    echo -e "${RED}║${RESET}  ${BOLD}⚠️  EXPERIMENTAL FEATURE - USE AT YOUR OWN RISK${RESET}                   ${RED}║${RESET}"
    echo -e "${RED}║${RESET}                                                                     ${RED}║${RESET}"
    echo -e "${RED}║${RESET}  Settings migration between desktop environments is fragile and     ${RED}║${RESET}"
    echo -e "${RED}║${RESET}  may not work correctly in all cases.                              ${RED}║${RESET}"
    echo -e "${RED}║${RESET}                                                                     ${RED}║${RESET}"
    echo -e "${RED}║${RESET}  • Some settings may not transfer properly                         ${RED}║${RESET}"
    echo -e "${RED}║${RESET}  • Desktop-specific configurations may cause issues                ${RED}║${RESET}"
    echo -e "${RED}║${RESET}  • Always test with --dry-run first                                ${RED}║${RESET}"
    echo -e "${RED}║${RESET}  • Ensure you have backups of important data                       ${RED}║${RESET}"
    echo -e "${RED}║${RESET}                                                                     ${RED}║${RESET}"
    echo -e "${RED}║${RESET}  This script is provided as-is with no guarantees.                 ${RED}║${RESET}"
    echo -e "${RED}║${RESET}                                                                     ${RED}║${RESET}"
    echo -e "${RED}╚═════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# Prompt for risk acceptance before migration
confirm_risk_acceptance() {
    # Skip confirmation in --yes mode
    if [[ "$YES_MODE" == "true" ]]; then
        return 0
    fi
    
    echo -e "${BOLD}${YELLOW}⚠️  WARNING:${RESET} This is an experimental feature. Some settings may not"
    echo "   transfer correctly between GNOME and KDE desktop environments."
    echo ""
    echo -en "${BOLD}   Do you understand and accept these risks?${RESET} [y/N]: "
    read -r response
    
    case "$response" in
        y|Y|yes|YES) return 0 ;;
        *)           return 1 ;;
    esac
}

# Helper function to extract font preferences from kdeglobals
extract_kde_font_preferences() {
    local src_file="$1"
    local font_settings=""
    
    if [[ ! -f "$src_file" ]]; then
        return 1
    fi
    
    # Extract font-related lines from kdeglobals
    # These are the common KDE font settings
    local font_keys=(
        "^font="
        "^menuFont="
        "^toolBarFont="
        "^desktopFont="
        "^fixed="  # Monospace font
    )
    
    for key in "${font_keys[@]}"; do
        local value
        value=$(grep -E "$key" "$src_file" 2>/dev/null | head -1)
        if [[ -n "$value" ]]; then
            font_settings+="$value\n"
        fi
    done
    
    if [[ -n "$font_settings" ]]; then
        echo -e "$font_settings"
        return 0
    fi
    
    return 1
}

# Helper function to extract font preferences from GTK settings.ini
extract_gtk_font_preferences() {
    local src_file="$1"
    
    if [[ ! -f "$src_file" ]]; then
        return 1
    fi
    
    # Extract font-name from GTK settings.ini
    local font_name
    font_name=$(grep -E "^font-name=" "$src_file" 2>/dev/null | head -1)
    
    if [[ -n "$font_name" ]]; then
        echo "$font_name"
        return 0
    fi
    
    return 1
}

# Check if dconf is available on the system
check_dconf_available() {
    command -v dconf &>/dev/null
}

# Extract dconf settings from the backup for GNOME-specific desktop settings
# This reads the backed-up dconf database and extracts only DE-agnostic settings
extract_dconf_settings() {
    local backup_dir="$1"
    local dconf_backup="$backup_dir/configs/.config/dconf/user"
    local dconf_local_backup="$backup_dir/configs/.local/share/dconf/user"
    
    # Check if dconf backup exists
    local dconf_db=""
    if [[ -f "$dconf_backup" ]]; then
        dconf_db="$dconf_backup"
    elif [[ -f "$dconf_local_backup" ]]; then
        dconf_db="$dconf_local_backup"
    else
        debug "No dconf database found in backup"
        return 1
    fi
    
    # Desktop-agnostic GNOME settings to migrate
    # These are settings that work across desktop environments
    # Format: "section:key" where section is the dconf path without leading slash
    local dconf_keys=(
        "org/gnome/desktop/interface:font-name"
        "org/gnome/desktop/interface:monospace-font-name"
        "org/gnome/desktop/interface:gtk-theme"
        "org/gnome/desktop/interface:icon-theme"
        "org/gnome/desktop/interface:cursor-theme"
        "org/gnome/desktop/interface:cursor-size"
        "org/gnome/desktop/interface:color-scheme"
        "org/gnome/desktop/interface:show-symbolic-icons"
        "org/gnome/desktop/interface:clock-format"
        "org/gnome/desktop/interface:clock-show-weekday"
        "org/gnome/desktop/background:picture-uri"
        "org/gnome/desktop/background:picture-uri-dark"
        "org/gnome/desktop/background:picture-options"
    )
    
    local extracted_settings=""
    local found_settings=0
    local temp_dir=""
    local cleanup_temp=false
    
    # Use dconf dump if dconf is available - this is the preferred method
    if check_dconf_available; then
        debug "Using dconf dump to extract settings from backup"
        
        # Create a temporary directory with a custom dconf profile
        temp_dir=$(mktemp -d)
        cleanup_temp=true
        
        # Create the dconf profile directory structure
        # dconf looks for databases in $XDG_CONFIG_HOME/dconf/ or ~/.config/dconf/
        # We set XDG_CONFIG_HOME to our temp directory so dconf finds the backup
        local profile_dir="$temp_dir/dconf"
        mkdir -p "$profile_dir"
        
        # Copy the backup database to the profile directory
        if cp "$dconf_db" "$profile_dir/user" 2>/dev/null; then
            # Run dconf dump with XDG_CONFIG_HOME pointing to our temp directory
            # This tells dconf to look for the database at $temp_dir/dconf/user
            local dconf_output
            if XDG_CONFIG_HOME="$temp_dir" dconf dump / > "$temp_dir/dump" 2>/dev/null; then
                dconf_output=$(cat "$temp_dir/dump")
                debug "Successfully dumped dconf database"
            else
                debug "dconf dump failed, falling back to strings method"
                dconf_output=""
            fi
            
            # Parse the dconf dump output (INI-like format)
            # Format: [section] followed by key=value lines
            if [[ -n "$dconf_output" ]]; then
                local current_section=""
                while IFS= read -r line; do
                    # Check for section header [org/gnome/desktop/interface]
                    if [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
                        current_section="${BASH_REMATCH[1]}"
                        debug "Found section: $current_section"
                    # Check for key=value line (includes underscores in key names)
                    elif [[ "$line" =~ ^([a-zA-Z0-9_-]+)=(.*)$ ]]; then
                        local key="${BASH_REMATCH[1]}"
                        local value="${BASH_REMATCH[2]}"
                        
                        # Build the full dconf path
                        local full_key="$current_section:$key"
                        
                        # Check if this key is in our list of keys to migrate
                        for target_key in "${dconf_keys[@]}"; do
                            if [[ "$full_key" == "$target_key" ]]; then
                                # Convert to dconf write format: /path/to/key:value
                                local dconf_path="/${current_section//\.//}/$key"
                                local setting_line="$dconf_path:$value"
                                extracted_settings+="$setting_line
"
                                ((found_settings++)) || true
                                debug "Found dconf setting: $setting_line"
                                break
                            fi
                        done
                    fi
                done <<< "$dconf_output"
            fi
        else
            debug "Failed to copy dconf database to temp directory"
        fi
    fi
    
    # Fallback to strings method if dconf dump didn't work or dconf not available
    if [[ $found_settings -eq 0 ]]; then
        if ! check_dconf_available; then
            warn "dconf command not available, using fallback 'strings' method"
            warn "This method may not reliably extract all settings"
        else
            debug "dconf dump found no settings, trying strings fallback"
        fi
        
        # Parse the database file directly using strings
        # This is a fallback that may not work reliably for all dconf formats
        local dconf_text
        dconf_text=$(strings "$dconf_db" 2>/dev/null | head -500) || true
        
        if [[ -n "$dconf_text" ]]; then
            # Old format keys for strings fallback (with trailing colon)
            local old_format_keys=(
                "/org/gnome/desktop/interface/font-name:"
                "/org/gnome/desktop/interface/monospace-font-name:"
                "/org/gnome/desktop/interface/gtk-theme:"
                "/org/gnome/desktop/interface/icon-theme:"
                "/org/gnome/desktop/interface/cursor-theme:"
                "/org/gnome/desktop/interface/cursor-size:"
                "/org/gnome/desktop/interface/color-scheme:"
                "/org/gnome/desktop/interface/show-symbolic-icons:"
                "/org/gnome/desktop/interface/clock-format:"
                "/org/gnome/desktop/interface/clock-show-weekday:"
                "/org/gnome/desktop/background/picture-uri:"
                "/org/gnome/desktop/background/picture-uri-dark:"
                "/org/gnome/desktop/background/picture-options:"
            )
            
            for key in "${old_format_keys[@]}"; do
                # Remove trailing colon for matching
                local key_pattern="${key%:}"
                local value
                
                value=$(echo "$dconf_text" | grep -E "^$key_pattern" | head -1)
                
                if [[ -n "$value" ]]; then
                    extracted_settings+="$value
"
                    ((found_settings++)) || true
                    debug "Found dconf setting (strings fallback): $value"
                fi
            done
        fi
    fi
    
    # Clean up temporary directory
    if [[ "$cleanup_temp" == "true" && -n "$temp_dir" && -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"
    fi
    
    if [[ $found_settings -gt 0 ]]; then
        echo -e "$extracted_settings"
        return 0
    fi
    
    return 1
}

# Migrate dconf settings to the target system
migrate_dconf_settings() {
    local category="$1"
    local paths="${SETTING_PATHS[$category]}"
    local migrated=0
    local skipped=0
    local errors=0
    
    info "Migrating GNOME dconf settings..."
    
    # Check if dconf is available
    if ! check_dconf_available; then
        warn "dconf is not installed on this system. Cannot migrate GNOME settings."
        warn "Install dconf with: sudo rpm-ostree install dconf"
        return 1
    fi
    
    # Extract dconf settings from backup
    local dconf_settings
    if ! dconf_settings=$(extract_dconf_settings "$BACKUP_DIR"); then
        debug "No dconf settings found in backup to migrate"
        ((skipped++)) || true
        
        # Store results
        FONT_MIGRATED=0
        FONT_SKIPPED=$skipped
        FONT_ERRORS=0
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} Would apply the following dconf settings:"
        echo "$dconf_settings" | sed 's/^/    /'
        ((migrated++)) || true
        
        FONT_MIGRATED=$migrated
        FONT_SKIPPED=$skipped
        FONT_ERRORS=$errors
        return 0
    fi
    
    # Apply each dconf setting individually
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        local key="${line%%:*}"
        local value="${line#*:}"
        
        # Skip keys that don't look valid
        # dconf keys must start with / and contain only valid characters
        if [[ ! "$key" =~ ^/[^[:space:]]+$ ]]; then
            debug "Skipping invalid key format: $key"
            continue
        fi
        
        # Additional validation: ensure key doesn't contain dangerous patterns
        if [[ "$key" =~ \.\. ]]; then
            debug "Skipping key with parent directory reference: $key"
            continue
        fi
        
        # Apply the setting using dconf
        if dconf write "$key" "$value" 2>/dev/null; then
            print_success "Applied dconf setting: $key"
            ((migrated++)) || true
        else
            print_error "Failed to apply dconf setting: $key"
            ((errors++)) || true
        fi
    done <<< "$dconf_settings"
    
    # Also migrate wallpaper files if they exist
    local wallpaper_paths=".local/share/backgrounds .wallpaper pictures/Wallpapers pictures/Wallpaper"
    for wall_path in $wallpaper_paths; do
        local src="$BACKUP_DIR/configs/$wall_path"
        local dest="$HOME/$wall_path"
        
        if [[ -e "$src" ]]; then
            local dest_parent
            dest_parent=$(dirname "$dest")
            
            if mkdir -p "$dest_parent" 2>/dev/null; then
                if cp -a "$src" "$dest" 2>/dev/null; then
                    print_success "Migrated wallpaper: $dest"
                else
                    print_error "Failed to migrate wallpaper: $dest"
                fi
            fi
        fi
    done
    
    # Store results
    FONT_MIGRATED=$migrated
    FONT_SKIPPED=$skipped
    FONT_ERRORS=$errors
}

# Helper function to migrate font preferences to target config
migrate_font_preferences() {
    local category="$1"
    local paths="${SETTING_PATHS[$category]}"
    local migrated=0
    local skipped=0
    local errors=0
    
    info "Migrating font preferences..."
    
    for path in $paths; do
        local src="$BACKUP_DIR/configs/$path"
        
        # Handle kdeglobals
        if [[ "$path" == ".config/kdeglobals" ]]; then
            local dest="$HOME/.config/kdeglobals"
            
            if [[ ! -f "$src" ]]; then
                debug "Source not found: $src"
                continue
            fi
            
            local font_settings
            if font_settings=$(extract_kde_font_preferences "$src"); then
                if [[ "$DRY_RUN" == "true" ]]; then
                    echo -e "${YELLOW}[DRY-RUN]${RESET} Would extract font preferences from: $src"
                    echo "  Font settings found:"
                    echo "$font_settings" | sed 's/^/    /'
                    ((migrated++)) || true
                    continue
                fi
                
                # Create or append to target file
                local dest_parent
                dest_parent=$(dirname "$dest")
                
                if mkdir -p "$dest_parent" 2>/dev/null; then
                    # Append font settings to existing file or create new
                    if [[ -f "$dest" ]]; then
                        # Check if font settings already exist
                        if grep -q "^font=" "$dest" 2>/dev/null; then
                            # Update existing font settings
                            local tmp_file
                            tmp_file=$(mktemp)
                            
                            # Remove existing font settings and add new ones
                            grep -v -E "^(font|menuFont|toolBarFont|desktopFont|fixed)=" "$dest" > "$tmp_file" 2>/dev/null || true
                            echo -e "$font_settings" >> "$tmp_file"
                            
                            if mv "$tmp_file" "$dest" 2>/dev/null; then
                                print_success "Updated font preferences in: $dest"
                                ((migrated++)) || true
                            else
                                print_error "Failed to update font preferences: $dest"
                                ((errors++)) || true
                            fi
                        else
                            # No existing font settings, just append
                            echo -e "$font_settings" >> "$dest"
                            print_success "Added font preferences to: $dest"
                            ((migrated++)) || true
                        fi
                    else
                        # Target doesn't exist, create with font settings
                        echo -e "$font_settings" > "$dest"
                        print_success "Created font preferences in: $dest"
                        ((migrated++)) || true
                    fi
                else
                    print_error "Failed to create directory: $dest_parent"
                    ((errors++)) || true
                fi
            else
                debug "No font preferences found in: $src"
                ((skipped++)) || true
            fi
        
        # Handle GTK3/GTK4 settings.ini
        elif [[ "$path" == ".config/gtk-3.0" || "$path" == ".config/gtk-4.0" ]]; then
            local src_ini="$src/settings.ini"
            local dest_dir="$HOME/$path"
            local dest_ini="$dest_dir/settings.ini"
            
            if [[ ! -f "$src_ini" ]]; then
                debug "Source not found: $src_ini"
                continue
            fi
            
            local font_setting
            if font_setting=$(extract_gtk_font_preferences "$src_ini"); then
                if [[ "$DRY_RUN" == "true" ]]; then
                    echo -e "${YELLOW}[DRY-RUN]${RESET} Would extract font preference from: $src_ini"
                    echo "  Font setting found: $font_setting"
                    ((migrated++)) || true
                    continue
                fi
                
                if mkdir -p "$dest_dir" 2>/dev/null; then
                    if [[ -f "$dest_ini" ]]; then
                        # Check if font-name already exists
                        if grep -q "^font-name=" "$dest_ini" 2>/dev/null; then
                            local tmp_file
                            tmp_file=$(mktemp)
                            
                            # Remove existing font-name and add new one
                            grep -v "^font-name=" "$dest_ini" > "$tmp_file" 2>/dev/null || true
                            echo "$font_setting" >> "$tmp_file"
                            
                            if mv "$tmp_file" "$dest_ini" 2>/dev/null; then
                                print_success "Updated font preference in: $dest_ini"
                                ((migrated++)) || true
                            else
                                print_error "Failed to update font preference: $dest_ini"
                                ((errors++)) || true
                            fi
                        else
                            echo "$font_setting" >> "$dest_ini"
                            print_success "Added font preference to: $dest_ini"
                            ((migrated++)) || true
                        fi
                    else
                        # Create new settings.ini with just the font setting
                        echo "[Settings]" > "$dest_ini"
                        echo "$font_setting" >> "$dest_ini"
                        print_success "Created font preference in: $dest_ini"
                        ((migrated++)) || true
                    fi
                else
                    print_error "Failed to create directory: $dest_dir"
                    ((errors++)) || true
                fi
            else
                debug "No font preference found in: $src_ini"
                ((skipped++)) || true
            fi
        fi
    done
    
    # Store results in global variables for the category function
    FONT_MIGRATED=$migrated
    FONT_SKIPPED=$skipped
    FONT_ERRORS=$errors
}

migrate_category() {
    local category="$1"
    local paths="${SETTING_PATHS[$category]}"
    local migrated=0
    local skipped=0
    local errors=0

    # Special handling for keychain/wallet - show compatibility warning
    if [[ "$category" == "keychain" ]]; then
        warn "Keychain/Wallet migration attempted. Note: GNOME keyring and KWallet"
        warn "may have compatibility issues when migrating between different DEs."
        info "If migration fails, you may need to re-enter credentials manually."
        echo ""
    fi

    # Special handling for dconf - use dconf to extract and apply settings
    if [[ "$category" == "dconf" ]]; then
        migrate_dconf_settings "$category"
        migrated=$FONT_MIGRATED
        skipped=$FONT_SKIPPED
        errors=$FONT_ERRORS
        
        if [[ $migrated -gt 0 ]]; then
            print_success "Migrated $migrated dconf settings"
        fi
        if [[ $skipped -gt 0 ]]; then
            warn "Skipped $skipped dconf settings"
        fi
        if [[ $errors -gt 0 ]]; then
            error "Encountered $errors errors while migrating dconf settings"
        fi
        return 0
    fi

    # Special handling for fonts - extract font preferences from config files
    if [[ "$category" == "fonts" ]]; then
        migrate_font_preferences "$category"
        migrated=$FONT_MIGRATED
        skipped=$FONT_SKIPPED
        errors=$FONT_ERRORS
        
        if [[ $migrated -gt 0 ]]; then
            print_success "Migrated $migrated font preference items"
        fi
        if [[ $skipped -gt 0 ]]; then
            warn "Skipped $skipped font preference items"
        fi
        if [[ $errors -gt 0 ]]; then
            error "Encountered $errors errors while migrating font preferences"
        fi
        return 0
    fi

    # Special handling for icon/cursor themes - filter out default DE themes
    local exclude_patterns=""
    if [[ "$category" == "icon-themes" || "$category" == "cursor-themes" ]]; then
        exclude_patterns="Adwaita breeze breeze-dark gnome hicolor oxygen yaru"
    fi

    info "Migrating $category..."

    for path in $paths; do
        local src="$BACKUP_DIR/configs/$path"
        local dest="$HOME/$path"

        if [[ ! -e "$src" ]]; then
            debug "Source not found: $src"
            ((skipped++)) || true
            continue
        fi

        if [[ -e "$dest" ]]; then
            warn "Destination exists, skipping: $dest"
            ((skipped++)) || true
            continue
        fi

        local dest_parent
        dest_parent=$(dirname "$dest")

        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "${YELLOW}[DRY-RUN]${RESET} Would migrate: $src -> $dest"
            ((migrated++)) || true
            continue
        fi

        if mkdir -p "$dest_parent" 2>/dev/null; then
            if cp -a "$src" "$dest" 2>/dev/null; then
                print_success "Migrated: $dest"
                ((migrated++)) || true
            else
                print_error "Failed to migrate: $dest"
                ((errors++)) || true
            fi
        else
            print_error "Failed to create directory: $dest_parent"
            ((errors++)) || true
        fi
    done

    if [[ $migrated -gt 0 ]]; then
        print_success "Migrated $migrated items for $category"
    fi
    if [[ $skipped -gt 0 ]]; then
        warn "Skipped $skipped items for $category"
    fi
    if [[ $errors -gt 0 ]]; then
        error "Encountered $errors errors while migrating $category"
    fi
}

migrate_all_selected() {
    local selected=("$@")

    if [[ ${#selected[@]} -eq 0 ]]; then
        warn "No settings selected for migration"
        return 0
    fi

    print_header "MIGRATING SETTINGS"

    local total_migrated=0

    for category in "${selected[@]}"; do
        migrate_category "$category"
    done

    print_section "MIGRATION COMPLETE"
    echo ""
    echo -e "${GREEN}Settings migration completed!${RESET}"
    echo ""
    echo "You may need to log out and back in for some changes to take effect."
    echo ""
}

show_preview() {
    print_header "SETTINGS PREVIEW"

    echo ""
    echo -e "${BOLD}Backup Directory:${RESET} $BACKUP_DIR"
    echo ""

    echo -e "${BOLD}Available Settings:${RESET}"
    echo ""

    for category in "${!SETTING_CATEGORIES[@]}"; do
        local desc="${SETTING_CATEGORIES[$category]}"
        local item_count
        item_count=$(get_category_item_count "$category")

        if [[ $item_count -gt 0 ]]; then
            echo -e "  ${GREEN}✓${RESET} $desc - $item_count items"
        else
            echo -e "  ${YELLOW}○${RESET} $desc - not found in backup"
        fi
    done

    echo ""
    echo "Use --all to migrate everything, or run interactively to choose."
    echo ""
}

interactive_select() {
    local ui_type="$1"

    print_header "SELECT SETTINGS TO MIGRATE"

    echo ""
    echo -e "${BOLD}Backup Directory:${RESET} $BACKUP_DIR"
    echo ""
    echo "Select which settings to migrate. Press Space to toggle, Enter to confirm."
    echo ""

    local menu_options
    menu_options=$(build_menu_options)

    local selected
    selected=$(show_checkbox_menu "$ui_type" "Settings Migration" \
        "Select settings to migrate:" \
        "$menu_options")

    SELECTED_SETTINGS=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && SELECTED_SETTINGS+=("$line")
    done <<< "$selected"

    if [[ ${#SELECTED_SETTINGS[@]} -eq 0 ]]; then
        echo ""
        warn "No settings selected. Exiting."
        exit 0
    fi

    echo ""
    echo -e "${BOLD}Selected settings:${RESET}"
    for setting in "${SELECTED_SETTINGS[@]}"; do
        echo "  - ${SETTING_CATEGORIES[$setting]:-$setting}"
    done
    echo ""

    if ! confirm "Proceed with migration?" "y"; then
        echo "Migration cancelled."
        exit 0
    fi
}

main() {
    parse_args "$@"

    print_header "BLUEFIN ↔ AURORA SETTINGS MIGRATOR"
    echo "              Post-Migration Settings"

    # Show experimental warning banner (always displayed)
    show_experimental_warning

    check_dependencies

    detect_backup_dir

    info "Using backup directory: $BACKUP_DIR"

    if [[ "$DRY_RUN" == "true" ]]; then
        show_preview
        exit 0
    fi

    # Require explicit risk acceptance before proceeding
    if ! confirm_risk_acceptance; then
        echo "Migration cancelled."
        exit 0
    fi

    if [[ "$MIGRATE_ALL" == "true" ]]; then
        local available_settings
        available_settings=$(get_available_settings)

        SELECTED_SETTINGS=()
        while IFS= read -r setting; do
            [[ -n "$setting" ]] && SELECTED_SETTINGS+=("$setting")
        done <<< "$available_settings"

        if [[ ${#SELECTED_SETTINGS[@]} -eq 0 ]]; then
            warn "No migratable settings found in backup"
            exit 0
        fi

        print_section "MIGRATING ALL SETTINGS"
        echo ""
        echo "Selected settings:"
        for setting in "${SELECTED_SETTINGS[@]}"; do
            echo "  - ${SETTING_CATEGORIES[$setting]:-$setting}"
        done
        echo ""

        if ! confirm "Proceed?" "y"; then
            echo "Migration cancelled."
            exit 0
        fi

        migrate_all_selected "${SELECTED_SETTINGS[@]}"
        exit 0
    fi

    local ui_type
    ui_type=$(check_ui_availability)

    if [[ "$ui_type" == "none" ]]; then
        warn "No interactive UI available (whiptail/dialog not installed)"
        warn "Using text-based selection"

        show_preview

        echo "Enter categories to migrate (space-separated, e.g., 'fonts keychain wallpaper'): "
        echo ""
        local available
        available=$(get_available_settings)
        echo "Available categories:"
        while IFS= read -r cat; do
            [[ -n "$cat" ]] && echo "  - $cat"
        done <<< "$available"
        echo ""
        echo -en "> "
        read -r input

        SELECTED_SETTINGS=()
        for word in $input; do
            # Validate that the category exists
            local valid_category=false
            for cat in "${!SETTING_CATEGORIES[@]}"; do
                if [[ "$word" == "$cat" ]]; then
                    valid_category=true
                    break
                fi
            done
            if [[ "$valid_category" == "true" ]]; then
                SELECTED_SETTINGS+=("$word")
            else
                warn "Unknown category: $word"
            fi
        done

        if [[ ${#SELECTED_SETTINGS[@]} -eq 0 ]]; then
            warn "No settings selected. Exiting."
            exit 0
        fi

        migrate_all_selected "${SELECTED_SETTINGS[@]}"
    else
        interactive_select "$ui_type"
        migrate_all_selected "${SELECTED_SETTINGS[@]}"
    fi
}

main "$@"
