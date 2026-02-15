#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

DATA_DIR="$ROOT_DIR/data"

fetch_and_parse() {
    local url="$1"
    
    local content
    if ! content=$(curl -sL "$url" 2>/dev/null); then
        echo "ERROR: Failed to fetch $url" >&2
        return 1
    fi
    
    local flatpaks
    flatpaks=$(echo "$content" | grep -E '^flatpak "' | sed 's/flatpak "\([^"]*\)"/\1/' | sort -u)
    
    if [[ -z "$flatpaks" ]]; then
        echo "ERROR: No flatpaks found in $url" >&2
        return 1
    fi
    
    echo "$flatpaks"
}

save_snapshot() {
    local de="$1"
    local url="$2"
    local flatpaks="$3"
    
    mkdir -p "$DATA_DIR"
    
    local timestamp
    timestamp=$(date -Iseconds)
    
    local snapshot_file="$DATA_DIR/${de}-flatpaks-snapshot.txt"
    
    {
        echo "# $de-specific flatpaks snapshot"
        echo "# Source: $url"
        echo "# Updated: $timestamp"
        echo ""
        echo "$flatpaks"
    } > "$snapshot_file"
    
    echo "Saved snapshot: $snapshot_file"
}

compare_with_previous() {
    local de="$1"
    local new_flatpaks="$2"
    
    local snapshot_file="$DATA_DIR/${de}-flatpaks-snapshot.txt"
    
    if [[ ! -f "$snapshot_file" ]]; then
        echo "No previous snapshot found for $de"
        return 0
    fi
    
    local old_flatpaks
    old_flatpaks=$(grep -v '^#' "$snapshot_file" | grep -v '^$' | sort -u)
    
    local added removed
    
    added=$(comm -13 <(echo "$old_flatpaks") <(echo "$new_flatpaks"))
    removed=$(comm -23 <(echo "$old_flatpaks") <(echo "$new_flatpaks"))
    
    if [[ -n "$added" || -n "$removed" ]]; then
        echo ""
        echo "Changes detected for $de:"
        if [[ -n "$added" ]]; then
            echo "  Added:"
            echo "$added" | while read -r app; do
                echo "    + $app"
            done
        fi
        if [[ -n "$removed" ]]; then
            echo "  Removed:"
            echo "$removed" | while read -r app; do
                echo "    - $app"
            done
        fi
        return 1
    else
        echo "No changes detected for $de"
        return 0
    fi
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
    local changed=false
    local failed=0
    
    source "$ROOT_DIR/lib/flatpaks.sh"
    
    mkdir -p "$DATA_DIR"
    
    echo "Fetching Bluefin (GNOME) flatpaks..."
    local bluefin_flatpaks
    if bluefin_flatpaks=$(fetch_and_parse "$BLUEFIN_BREWFILE_URL"); then
        echo "Found $(echo "$bluefin_flatpaks" | grep -c .) flatpaks"
        if ! compare_with_previous "gnome" "$bluefin_flatpaks"; then
            changed=true
        fi
        save_snapshot "gnome" "$BLUEFIN_BREWFILE_URL" "$bluefin_flatpaks"
    else
        ((failed++)) || true
    fi
    
    echo ""
    echo "Fetching Aurora (KDE) flatpaks..."
    local aurora_flatpaks
    if aurora_flatpaks=$(fetch_and_parse "$AURORA_BREWFILE_URL"); then
        echo "Found $(echo "$aurora_flatpaks" | grep -c .) flatpaks"
        if ! compare_with_previous "kde" "$aurora_flatpaks"; then
            changed=true
        fi
        save_snapshot "kde" "$AURORA_BREWFILE_URL" "$aurora_flatpaks"
    else
        ((failed++)) || true
    fi
    
    echo ""
    if [[ "$changed" == "true" ]]; then
        set_output "changed" "true"
    fi
    
    if [[ $failed -gt 0 ]]; then
        set_output "failed" "true"
        echo "ERROR: $failed fetch(es) failed"
        exit 1
    fi
    
    echo "Done"
}

main "$@"
