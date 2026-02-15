#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        warn "Some preflight checks require sudo. You may be prompted for your password."
    fi
}

check_bootc_installed() {
    print_section "Checking bootc Installation"
    
    if command -v bootc &>/dev/null; then
        local version
        version=$(bootc --version 2>/dev/null || echo "unknown")
        print_success "bootc is installed (version: $version)"
        return 0
    else
        print_error "bootc is not installed"
        return 1
    fi
}

check_layered_packages() {
    print_section "Checking Layered Packages"
    
    if ! command -v rpm-ostree &>/dev/null; then
        warn "rpm-ostree not found, skipping layered package check"
        return 0
    fi
    
    local status
    status=$(rpm-ostree status --json 2>/dev/null || echo "{}")
    
    local layered
    layered=$(echo "$status" | jq -r '.deployments[0].layered-packages // [] | length' 2>/dev/null || echo "0")
    
    if [[ "$layered" -gt 0 ]]; then
        print_warning "Found $layered layered package(s)"
        echo ""
        echo "$status" | jq -r '.deployments[0]["layered-packages"] // [] | .[]' 2>/dev/null | while read -r pkg; do
            echo "  - $pkg"
        done
        echo ""
        warn "Layered packages may not persist after rebase."
        echo "  Consider running: rpm-ostree reset"
        echo ""
        
        if ! confirm "Continue with layered packages present?" "n"; then
            return 1
        fi
    else
        print_success "No layered packages detected"
    fi
    
    return 0
}

check_pinned_deployment() {
    print_section "Checking Pinned Deployment"
    
    if ! command -v ostree &>/dev/null; then
        warn "ostree not found, skipping pinned deployment check"
        return 0
    fi
    
    local pinned
    pinned=$(ostree admin status 2>/dev/null | grep -c "^\* " || echo "0")
    
    if [[ "$pinned" -ge 1 ]]; then
        print_success "Current deployment appears to be pinned or is the default"
    else
        print_warning "Current deployment may not be pinned"
        echo "  Consider running: sudo ostree admin pin 0"
        echo "  This allows rollback if something goes wrong."
    fi
    
    return 0
}

check_display_manager_user() {
    local target_de="$1"
    local dm_user
    local dm_name
    
    print_section "Checking Display Manager User"
    
    dm_user=$(get_display_manager "$target_de")
    dm_name="$dm_user"
    
    if [[ -z "$dm_user" ]]; then
        warn "Could not determine expected display manager"
        return 0
    fi
    
    echo "  Expected display manager: $dm_name"
    echo ""
    
    if getent passwd "$dm_user" &>/dev/null; then
        print_success "$dm_user user exists in /etc/passwd"
    else
        print_warning "$dm_user user NOT found in /etc/passwd"
        echo ""
        echo "  This is expected when switching desktop environments."
        echo "  The user should be created automatically on first boot."
        echo ""
        echo "  If the display manager fails to start after rebase, run:"
        echo "    sudo systemd-sysusers"
    fi
    
    if [[ $EUID -eq 0 ]] || sudo -n true 2>/dev/null; then
        if getent shadow "$dm_user" &>/dev/null 2>&1; then
            print_success "$dm_user has /etc/shadow entry"
        else
            print_warning "$dm_user missing from /etc/shadow"
            echo "  This is normal for a new DE. Will be created on boot."
        fi
    else
        echo "  (Cannot check /etc/shadow without sudo)"
    fi
    
    return 0
}

check_flathub_remote() {
    print_section "Checking Flatpak Configuration"
    
    if ! command -v flatpak &>/dev/null; then
        warn "flatpak not found, skipping remote check"
        return 0
    fi
    
    if flatpak remotes --system 2>/dev/null | grep -q "flathub"; then
        print_success "Flathub remote is configured (system)"
    else
        print_warning "Flathub remote not found (system)"
        echo "  After rebase, you may need to add it:"
        echo "    flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo"
    fi
    
    if flatpak remotes --user 2>/dev/null | grep -q "flathub"; then
        print_success "Flathub remote is configured (user)"
    fi
    
    return 0
}

check_disk_space() {
    print_section "Checking Disk Space"
    
    local home_avail
    local home_total
    
    home_avail=$(df -h "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
    home_total=$(df -h "$HOME" 2>/dev/null | awk 'NR==2 {print $2}')
    
    echo "  Home directory: $home_avail available of $home_total"
    
    local home_avail_kb
    home_avail_kb=$(df -k "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
    
    if [[ "$home_avail_kb" -lt 5242880 ]]; then
        print_warning "Less than 5GB available in home directory"
        echo "  Migration backup may require significant space."
        if ! confirm "Continue with limited disk space?" "n"; then
            return 1
        fi
    else
        print_success "Sufficient disk space available"
    fi
    
    return 0
}

check_running_processes() {
    print_section "Checking Running Processes"
    
    local important_processes=("flatpak" "brew" "distrobox" "podman" "docker")
    local running=()
    
    for proc in "${important_processes[@]}"; do
        if pgrep -x "$proc" &>/dev/null; then
            running+=("$proc")
        fi
    done
    
    if [[ ${#running[@]} -gt 0 ]]; then
        print_warning "The following processes are running: ${running[*]}"
        echo "  Consider closing applications before migration."
        echo ""
    else
        print_success "No conflicting processes detected"
    fi
    
    return 0
}

run_preflight_checks() {
    local target_de="$1"
    local failed=0
    
    print_header "PREFLIGHT CHECKS"
    
    check_bootc_installed || ((failed++))
    check_layered_packages || ((failed++))
    check_pinned_deployment || ((failed++))
    check_display_manager_user "$target_de" || ((failed++))
    check_flathub_remote || ((failed++))
    check_disk_space || ((failed++))
    check_running_processes || ((failed++))
    
    echo ""
    
    if [[ $failed -gt 0 ]]; then
        print_warning "$failed preflight check(s) failed or require attention"
        echo ""
        if ! confirm "Continue with warnings?" "n"; then
            return 1
        fi
    else
        print_success "All preflight checks passed"
    fi
    
    return 0
}

run_post_rebase_system_checks() {
    local expected_de="$1"
    local failed=0
    
    print_header "POST-REBASE SYSTEM CHECKS"
    
    print_section "Verifying Image"
    
    local current_image
    current_image=$(bootc status --json 2>/dev/null | jq -r '.status.booted.image.name // empty' || echo "")
    
    if [[ -n "$current_image" ]]; then
        print_success "Booted into: $current_image"
    else
        print_error "Could not verify current image"
        ((failed++))
    fi
    
    print_section "Checking Display Manager"
    
    local dm_user
    dm_user=$(get_display_manager "$expected_de")
    
    if [[ -n "$dm_user" ]]; then
        if getent passwd "$dm_user" &>/dev/null; then
            print_success "$dm_user display manager user exists"
        else
            print_warning "$dm_user display manager user missing"
            echo "  Attempting to create with systemd-sysusers..."
            
            if sudo systemd-sysusers 2>/dev/null; then
                if getent passwd "$dm_user" &>/dev/null; then
                    print_success "$dm_user user created successfully"
                else
                    print_error "Failed to create $dm_user user"
                    ((failed++))
                fi
            else
                print_error "systemd-sysusers failed"
                ((failed++))
            fi
        fi
    fi
    
    print_section "Checking Flathub"
    
    if flatpak remotes 2>/dev/null | grep -q "flathub"; then
        print_success "Flathub remote configured"
    else
        print_warning "Flathub remote not found, adding..."
        flatpak remote-add --if-not-exists --system flathub \
            https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    fi
    
    echo ""
    
    if [[ $failed -gt 0 ]]; then
        print_warning "$failed system check(s) failed"
        return 1
    else
        print_success "All system checks passed"
    fi
    
    return 0
}
