#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

BLUEFIN_BREWFILE_URL="https://raw.githubusercontent.com/projectbluefin/common/main/system_files/bluefin/usr/share/ublue-os/homebrew/system-flatpaks.Brewfile"
AURORA_BREWFILE_URL="https://raw.githubusercontent.com/get-aurora-dev/common/main/system_files/shared/usr/share/ublue-os/homebrew/system-flatpaks.Brewfile"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bluefin-aurora-migrate"
CACHE_EXPIRY_SECONDS=$((24 * 60 * 60))

fetch_brewfile() {
    local url="$1"
    local cache_file="$CACHE_DIR/$(echo "$url" | sha256sum | cut -d' ' -f1).brewfile"
    
    mkdir -p "$CACHE_DIR"
    
    if [[ -f "$cache_file" ]]; then
        local cache_age
        cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
        
        if [[ $cache_age -lt $CACHE_EXPIRY_SECONDS ]]; then
            debug "Using cached brewfile: $cache_file"
            cat "$cache_file"
            return 0
        fi
    fi
    
    debug "Fetching brewfile from: $url"
    
    local content
    if content=$(curl -sL "$url" 2>/dev/null); then
        echo "$content" > "$cache_file"
        echo "$content"
        return 0
    else
        warn "Failed to fetch brewfile from: $url"
        
        if [[ -f "$cache_file" ]]; then
            warn "Using stale cache"
            cat "$cache_file"
            return 0
        fi
        
        return 1
    fi
}

parse_flatpaks_from_brewfile() {
    local content="$1"
    
    echo "$content" | grep -E '^flatpak "' | sed 's/flatpak "\([^"]*\)"/\1/' | sort -u
}

get_de_flatpaks() {
    local de="$1"
    local url=""
    
    case "$de" in
        gnome) url="$BLUEFIN_BREWFILE_URL" ;;
        kde)   url="$AURORA_BREWFILE_URL" ;;
        *)     return 1 ;;
    esac
    
    local brewfile
    if brewfile=$(fetch_brewfile "$url"); then
        parse_flatpaks_from_brewfile "$brewfile"
        return 0
    else
        return 1
    fi
}

get_installed_flatpaks() {
    if ! command -v flatpak &>/dev/null; then
        return 1
    fi
    
    flatpak list --app --columns=application 2>/dev/null | tail -n +1 | sort -u
}

is_flatpak_installed() {
    local app_id="$1"
    flatpak list --app --columns=application 2>/dev/null | grep -q "^${app_id}$"
}

get_de_specific_flatpaks() {
    local de="$1"
    local installed_only="${2:-false}"
    
    local all_apps
    all_apps=$(get_de_flatpaks "$de") || return 1
    
    local pattern=""
    case "$de" in
        gnome) pattern="org\.gnome\.|org\.gtk\.Gtk3theme\.adw" ;;
        kde)   pattern="org\.kde\.|org\.gtk\.Gtk3theme\.Breeze" ;;
        *)     return 1 ;;
    esac
    
    while IFS= read -r app; do
        [[ -z "$app" ]] && continue
        
        if [[ ! "$app" =~ $pattern ]]; then
            continue
        fi
        
        if [[ "$installed_only" == "true" ]]; then
            if is_flatpak_installed "$app"; then
                echo "$app"
            fi
        else
            echo "$app"
        fi
    done <<< "$all_apps"
}

get_installed_gnome_flatpaks() {
    get_de_specific_flatpaks "gnome" "true"
}

get_installed_kde_flatpaks() {
    get_de_specific_flatpaks "kde" "true"
}

remove_flatpak() {
    local app_id="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} Would remove flatpak: $app_id"
        return 0
    fi
    
    if ! is_flatpak_installed "$app_id"; then
        debug "Flatpak not installed: $app_id"
        return 0
    fi
    
    info "Removing flatpak: $app_id"
    
    if flatpak uninstall -y "$app_id" 2>/dev/null; then
        print_success "Removed: $app_id"
    else
        print_error "Failed to remove: $app_id"
        return 1
    fi
}

install_flatpak() {
    local app_id="$1"
    local remote="${2:-flathub}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} Would install flatpak: $app_id"
        return 0
    fi
    
    if is_flatpak_installed "$app_id"; then
        debug "Flatpak already installed: $app_id"
        return 0
    fi
    
    info "Installing flatpak: $app_id"
    
    if flatpak install -y "$remote" "$app_id" 2>/dev/null; then
        print_success "Installed: $app_id"
    else
        print_error "Failed to install: $app_id"
        return 1
    fi
}

remove_de_flatpaks() {
    local de="$1"
    local count=0
    local failed=0
    
    print_section "Removing $de-specific Flatpaks"
    
    local apps
    apps=$(get_de_specific_flatpaks "$de" "true")
    
    if [[ -z "$apps" ]]; then
        print_success "No $de-specific flatpaks found to remove"
        return 0
    fi
    
    local app_count
    app_count=$(echo "$apps" | grep -c . || echo 0)
    
    echo ""
    echo "Found $app_count $de-specific flatpak(s) to remove:"
    echo "$apps" | while read -r app; do
        [[ -n "$app" ]] && echo "  - $app"
    done
    echo ""
    
    if ! confirm "Remove these $de flatpaks?" "y"; then
        echo "Skipping flatpak removal."
        return 0
    fi
    
    while IFS= read -r app; do
        [[ -z "$app" ]] && continue
        if remove_flatpak "$app"; then
            ((count++)) || true
        else
            ((failed++)) || true
        fi
    done <<< "$apps"
    
    echo ""
    if [[ $failed -gt 0 ]]; then
        print_warning "Removed $count flatpaks, $failed failed"
    else
        print_success "Removed $count $de flatpaks"
    fi
}

install_de_flatpaks() {
    local de="$1"
    local count=0
    local failed=0
    
    print_section "Installing $de-specific Flatpaks"
    
    local all_apps
    all_apps=$(get_de_specific_flatpaks "$de" "false") || {
        print_error "Could not fetch $de flatpak list"
        return 1
    }
    
    if [[ -z "$all_apps" ]]; then
        print_success "No $de-specific flatpaks to install"
        return 0
    fi
    
    local to_install=()
    while IFS= read -r app; do
        [[ -z "$app" ]] && continue
        if ! is_flatpak_installed "$app"; then
            to_install+=("$app")
        fi
    done <<< "$all_apps"
    
    if [[ ${#to_install[@]} -eq 0 ]]; then
        print_success "All $de core flatpaks already installed"
        return 0
    fi
    
    echo ""
    echo "Found ${#to_install[@]} $de flatpak(s) available to install:"
    for app in "${to_install[@]}"; do
        echo "  + $app"
    done
    echo ""
    echo -e "${YELLOW}Note: This will install the default $de-specific flatpaks.${RESET}"
    echo "      Shared apps like Firefox and Thunderbird are not affected."
    echo ""
    
    if ! confirm "Install these $de flatpaks?" "n"; then
        echo "Skipping flatpak installation."
        return 0
    fi
    
    for app in "${to_install[@]}"; do
        if install_flatpak "$app"; then
            ((count++)) || true
        else
            ((failed++)) || true
        fi
    done
    
    echo ""
    if [[ $failed -gt 0 ]]; then
        print_warning "Installed $count flatpaks, $failed failed"
    else
        print_success "Installed $count $de flatpaks"
    fi
}

offer_flatpak_swap() {
    local previous_de="$1"
    local target_de="$2"
    
    print_section "Desktop-Specific Flatpaks"
    
    local previous_apps
    previous_apps=$(get_de_specific_flatpaks "$previous_de" "true") || {
        warn "Could not fetch $previous_de flatpak list"
        return 1
    }
    
    local target_apps
    target_apps=$(get_de_specific_flatpaks "$target_de" "false") || {
        warn "Could not fetch $target_de flatpak list"
        return 1
    }
    
    local previous_count
    previous_count=$(echo "$previous_apps" | grep -c . 2>/dev/null || echo 0)
    
    local target_count
    target_count=$(echo "$target_apps" | grep -c . 2>/dev/null || echo 0)
    
    echo ""
    echo -e "${BOLD}Fetched flatpak lists from:${RESET}"
    case "$previous_de" in
        gnome) echo "  Bluefin: $BLUEFIN_BREWFILE_URL" ;;
        kde)   echo "  Aurora:  $AURORA_BREWFILE_URL" ;;
    esac
    echo ""
    
    if [[ $previous_count -gt 0 ]]; then
        echo "Installed $previous_de-specific flatpaks ($previous_count):"
        echo "$previous_apps" | while read -r app; do
            [[ -n "$app" ]] && echo "  - $app"
        done
    else
        echo "No $previous_de-specific flatpaks found installed."
    fi
    
    echo ""
    echo "Default $target_de-specific flatpaks ($target_count):"
    
    local shown=0
    while IFS= read -r app; do
        [[ -z "$app" ]] && continue
        
        if is_flatpak_installed "$app"; then
            echo "  ✓ $app (already installed)"
        else
            echo "  + $app"
        fi
    done <<< "$target_apps"
    
    echo ""
    echo -e "${CYAN}Note: Shared apps (Firefox, Thunderbird, etc.) are not affected.${RESET}"
    echo ""
    
    local action=""
    echo "Options:"
    echo "  1. Swap: Remove $previous_de flatpaks, install $target_de flatpaks"
    echo "  2. Install only: Just install $target_de flatpaks"
    echo "  3. Remove only: Just remove $previous_de flatpaks"
    echo "  4. Skip: Don't modify flatpaks"
    echo ""
    read -rp "Select action [1-4]: " action
    
    case "$action" in
        1)
            remove_de_flatpaks "$previous_de"
            install_de_flatpaks "$target_de"
            ;;
        2)
            install_de_flatpaks "$target_de"
            ;;
        3)
            remove_de_flatpaks "$previous_de"
            ;;
        4|"")
            echo "Skipping flatpak management."
            echo ""
            echo "You can manage flatpaks manually with:"
            echo "  flatpak list"
            echo "  flatpak install flathub <app-id>"
            echo "  flatpak uninstall <app-id>"
            echo "  ujust install-system-flatpaks"
            ;;
        *)
            echo "Invalid selection, skipping."
            ;;
    esac
}

run_flatpak_management() {
    local previous_de="$1"
    local target_de="$2"
    
    if ! command -v flatpak &>/dev/null; then
        warn "flatpak command not found, skipping flatpak management"
        return 0
    fi
    
    if ! flatpak remotes 2>/dev/null | grep -q "flathub"; then
        warn "Flathub remote not configured, skipping flatpak management"
        echo "  Add it with: flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo"
        return 0
    fi
    
    offer_flatpak_swap "$previous_de" "$target_de"
}
