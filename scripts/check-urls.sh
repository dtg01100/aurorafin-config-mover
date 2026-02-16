#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

FLATPAKS_FILE="$LIB_DIR/flatpaks.sh"

KNOWN_BLUEFIN_URLS=(
    "https://raw.githubusercontent.com/projectbluefin/common/main/system_files/bluefin/usr/share/ublue-os/homebrew/system-flatpaks.Brewfile"
    "https://raw.githubusercontent.com/projectbluefin/common/main/system_files/usr/share/ublue-os/homebrew/system-flatpaks.Brewfile"
    "https://raw.githubusercontent.com/ublue-os/bluefin/main/system_files/usr/share/ublue-os/homebrew/system-flatpaks.Brewfile"
)

KNOWN_AURORA_URLS=(
    "https://raw.githubusercontent.com/get-aurora-dev/common/main/system_files/shared/usr/share/ublue-os/homebrew/system-flatpaks.Brewfile"
    "https://raw.githubusercontent.com/ublue-os/aurora/main/system_files/shared/usr/share/ublue-os/homebrew/system-flatpaks.Brewfile"
    "https://raw.githubusercontent.com/ublue-os/aurora/main/system_files/usr/share/ublue-os/homebrew/system-flatpaks.Brewfile"
)

check_url() {
    local url="$1"
    local response
    
    if response=$(curl -sL -o /dev/null -w "%{http_code}" "$url" 2>/dev/null); then
        if [[ "$response" == "200" ]]; then
            return 0
        fi
    fi
    return 1
}

find_working_url() {
    local urls=("$@")
    
    for url in "${urls[@]}"; do
        if check_url "$url"; then
            echo "$url"
            return 0
        fi
    done
    return 1
}

validate_brewfile_content() {
    local url="$1"
    local content
    
    content=$(curl -sL "$url" 2>/dev/null) || return 1
    
    if echo "$content" | grep -qE '^flatpak "'; then
        return 0
    fi
    return 1
}

get_current_urls() {
    grep -E '^(BLUEFIN|AURORA)_BREWFILE_URL=' "$FLATPAKS_FILE" | sed 's/.*="\([^"]*\)"/\1/'
}

update_urls() {
    local bluefin_url="$1"
    local aurora_url="$2"
    
    sed -i "s|^BLUEFIN_BREWFILE_URL=.*|BLUEFIN_BREWFILE_URL=\"$bluefin_url\"|" "$FLATPAKS_FILE"
    sed -i "s|^AURORA_BREWFILE_URL=.*|AURORA_BREWFILE_URL=\"$aurora_url\"|" "$FLATPAKS_FILE"
    
    echo "Updated URLs:"
    echo "  Bluefin Brewfile:"
    echo "    $bluefin_url"
    echo "  Aurora Brewfile:"
    echo "    $aurora_url"
}

set_output() {
    local name="$1"
    local value="$2"
    
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "$name=$value" >> "$GITHUB_OUTPUT"
    else
        echo "::set-output name=$name::$value"
    fi
}

main() {
    local failed=0
    local bluefin_needs_update=false
    local aurora_needs_update=false
    local new_bluefin_url=""
    local new_aurora_url=""
    
    local current_urls
    current_urls=$(get_current_urls)
    local BLUEFIN_BREWFILE_URL AURORA_BREWFILE_URL
    BLUEFIN_BREWFILE_URL=$(echo "$current_urls" | head -1)
    AURORA_BREWFILE_URL=$(echo "$current_urls" | tail -1)
    
    echo "Checking Brewfile URLs..."
    echo ""
    
    echo "Bluefin URL: $BLUEFIN_BREWFILE_URL"
    if check_url "$BLUEFIN_BREWFILE_URL" && validate_brewfile_content "$BLUEFIN_BREWFILE_URL"; then
        echo "  ✓ URL valid and contains flatpak entries"
    else
        echo "  ✗ URL check failed, searching for alternative..."
        bluefin_needs_update=true
        if new_bluefin_url=$(find_working_url "${KNOWN_BLUEFIN_URLS[@]}"); then
            echo "  → Found alternative: $new_bluefin_url"
        else
            echo "  ✗ No alternative URL found for Bluefin"
            ((failed++)) || true
        fi
    fi
    
    echo ""
    echo "Aurora URL: $AURORA_BREWFILE_URL"
    if check_url "$AURORA_BREWFILE_URL" && validate_brewfile_content "$AURORA_BREWFILE_URL"; then
        echo "  ✓ URL valid and contains flatpak entries"
    else
        echo "  ✗ URL check failed, searching for alternative..."
        aurora_needs_update=true
        if new_aurora_url=$(find_working_url "${KNOWN_AURORA_URLS[@]}"); then
            echo "  → Found alternative: $new_aurora_url"
        else
            echo "  ✗ No alternative URL found for Aurora"
            ((failed++)) || true
        fi
    fi
    
    if [[ "$bluefin_needs_update" == "true" || "$aurora_needs_update" == "true" ]]; then
        echo ""
        echo "URLs need updating..."
        
        [[ -z "$new_bluefin_url" ]] && new_bluefin_url="$BLUEFIN_BREWFILE_URL"
        [[ -z "$new_aurora_url" ]] && new_aurora_url="$AURORA_BREWFILE_URL"
        
        update_urls "$new_bluefin_url" "$new_aurora_url"
        
        echo ""
        set_output "needs_update" "true"
        exit 0
    fi
    
    echo ""
    if [[ $failed -gt 0 ]]; then
        set_output "failed" "true"
        echo "ERROR: $failed URL check(s) failed with no alternatives found"
        exit 1
    else
        echo "All URL checks passed"
        set_output "needs_update" "false"
    fi
}

main "$@"
