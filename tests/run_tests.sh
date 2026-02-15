#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

pass() {
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓${RESET} $1"
}

fail() {
    ((TESTS_FAILED++))
    echo -e "${RED}✗${RESET} $1"
    if [[ -n "${2:-}" ]]; then
        echo "  Expected: $2"
        echo "  Got: $3"
    fi
}

run_test() {
    local name="$1"
    ((TESTS_RUN++))
    echo -e "\n${YELLOW}Test: $name${RESET}"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-values should be equal}"
    
    if [[ "$expected" == "$actual" ]]; then
        pass "$msg"
    else
        fail "$msg" "$expected" "$actual"
    fi
}

assert_contains() {
    local needle="$1"
    local haystack="$2"
    local msg="${3:-string should contain substring}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$msg"
    else
        fail "$msg" "contains '$needle'" "'$haystack'"
    fi
}

assert_not_empty() {
    local value="$1"
    local msg="${2:-value should not be empty}"
    
    if [[ -n "$value" ]]; then
        pass "$msg"
    else
        fail "$msg" "non-empty" "empty"
    fi
}

assert_file_exists() {
    local file="$1"
    local msg="${2:-file should exist}"
    
    if [[ -f "$file" ]]; then
        pass "$msg"
    else
        fail "$msg" "$file exists" "file not found"
    fi
}

test_brewfile_parsing() {
    run_test "Brewfile parsing"
    
    local sample='flatpak "org.gnome.Nautilus"
flatpak "org.gnome.Terminal"
# comment
flatpak "org.mozilla.firefox"'
    
    local result
    result=$(echo "$sample" | grep -E '^flatpak "' | sed 's/flatpak "\([^"]*\)"/\1/' | sort -u)
    
    assert_equals "org.gnome.Nautilus
org.gnome.Terminal
org.mozilla.firefox" "$result" "parses flatpak IDs from Brewfile"
}

test_url_check() {
    run_test "URL accessibility check"
    
    local url="https://raw.githubusercontent.com/projectbluefin/common/main/system_files/bluefin/usr/share/ublue-os/homebrew/system-flatpaks.Brewfile"
    local response
    
    response=$(curl -sL -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    
    assert_equals "200" "$response" "Bluefin Brewfile URL is accessible"
    
    url="https://raw.githubusercontent.com/get-aurora-dev/common/main/system_files/shared/usr/share/ublue-os/homebrew/system-flatpaks.Brewfile"
    response=$(curl -sL -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    
    assert_equals "200" "$response" "Aurora Brewfile URL is accessible"
}

test_flatpak_fetch() {
    run_test "Flatpak list fetch"
    
    source "$ROOT_DIR/lib/flatpaks.sh"
    
    local bluefin_flatpaks
    bluefin_flatpaks=$(get_de_flatpaks "gnome")
    
    assert_not_empty "$bluefin_flatpaks" "Bluefin flatpak list not empty"
    assert_contains "org.gnome.Nautilus" "$bluefin_flatpaks" "Contains Nautilus"
    assert_contains "org.gnome.Calculator" "$bluefin_flatpaks" "Contains Calculator"
    
    local aurora_flatpaks
    aurora_flatpaks=$(get_de_flatpaks "kde")
    
    assert_not_empty "$aurora_flatpaks" "Aurora flatpak list not empty"
    assert_contains "org.kde.okular" "$aurora_flatpaks" "Contains Okular"
    assert_contains "org.kde.gwenview" "$aurora_flatpaks" "Contains Gwenview"
}

test_variant_parsing() {
    run_test "Variant parsing from Justfile"
    
    local sample='flavors := '"'"'(
    [main]=main
    [nvidia-open]=nvidia-open
)
tags := '"'"'(
    [stable]=stable
    [latest]=latest
)'
    
    local in_flavors=false
    local flavors=()
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^flavors.*= ]]; then
            in_flavors=true
            continue
        fi
        if [[ "$in_flavors" == "true" ]]; then
            if [[ "$line" == ")"* ]]; then
                break
            fi
            if [[ "$line" =~ \[([^\]]+)\]= ]]; then
                flavors+=("${BASH_REMATCH[1]}")
            fi
        fi
    done <<< "$sample"
    
    assert_equals "2" "${#flavors[@]}" "Parses 2 flavors"
    assert_equals "main" "${flavors[0]}" "First flavor is main"
    assert_equals "nvidia-open" "${flavors[1]}" "Second flavor is nvidia-open"
}

test_variant_sync() {
    run_test "Variant sync script"
    
    chmod +x "$ROOT_DIR/scripts/sync-variants.sh"
    
    "$ROOT_DIR/scripts/sync-variants.sh" >/dev/null 2>&1 || true
    
    assert_file_exists "$ROOT_DIR/data/variants-cache.json" "Cache file created"
    
    local cache_content
    cache_content=$(cat "$ROOT_DIR/data/variants-cache.json")
    
    assert_contains '"bluefin"' "$cache_content" "Contains bluefin section"
    assert_contains '"aurora"' "$cache_content" "Contains aurora section"
    assert_contains '"flavors"' "$cache_content" "Contains flavors"
    assert_contains '"tags"' "$cache_content" "Contains tags"
    assert_contains '"images"' "$cache_content" "Contains images"
}

test_image_detection() {
    run_test "Image detection from bootc status"
    
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/detect.sh"
    
    MOCK_BOOTC="ghcr.io/ublue-os/bluefin-dx:stable"
    
    local status
    status=$(get_bootc_status)
    
    local image
    image=$(echo "$status" | jq -r '.status.booted.image.name')
    
    assert_equals "ghcr.io/ublue-os/bluefin-dx:stable" "$image" "Detects image from mock"
    
    detect_current_image
    
    assert_equals "bluefin" "$SOURCE_FAMILY" "Detects bluefin family"
    assert_equals "gnome" "$SOURCE_DE" "Detects GNOME desktop"
    assert_equals "dx" "$SOURCE_VARIANT" "Detects dx variant"
    assert_equals "stable" "$SOURCE_TAG" "Detects stable tag"
}

test_rpm_ostree_fallback() {
    run_test "rpm-ostree fallback detection"
    
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/detect.sh"
    
    unset MOCK_BOOTC
    
    if command -v rpm-ostree &>/dev/null; then
        local status
        status=$(get_bootc_status)
        
        local image
        image=$(echo "$status" | jq -r '.status.booted.image.name // empty')
        
        if [[ -n "$image" ]]; then
            pass "rpm-ostree fallback returns image"
            assert_contains "ghcr.io/ublue-os/" "$image" "Image is from ublue-os"
        else
            pass "rpm-ostree fallback returns empty when no container image"
        fi
    else
        pass "rpm-ostree not available, skipping"
    fi
}

test_available_targets() {
    run_test "Available target generation"
    
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/detect.sh"
    
    MOCK_BOOTC="ghcr.io/ublue-os/bluefin-dx:stable"
    detect_current_image
    
    local targets
    targets=$(get_available_targets "$SOURCE_FAMILY" "$SOURCE_VARIANT" "$SOURCE_TAG")
    
    assert_not_empty "$targets" "Targets not empty"
    assert_contains "aurora-dx:stable" "$targets" "Contains matching Aurora DX stable"
}

test_config_path_loading() {
    run_test "Config path loading"
    
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/archive.sh"
    
    local gnome_count kde_count
    
    gnome_count=$(wc -l < "$ROOT_DIR/configs/gnome-paths.txt")
    kde_count=$(wc -l < "$ROOT_DIR/configs/kde-paths.txt")
    
    assert_not_empty "$gnome_count" "GNOME paths file has content"
    assert_not_empty "$kde_count" "KDE paths file has content"
    
    local gnome_paths
    gnome_paths=$(load_config_paths "gnome" 2>/dev/null || echo "")
    
    assert_contains ".config/gnome-shell" "$gnome_paths" "Contains gnome-shell path"
    assert_contains ".config/nautilus" "$gnome_paths" "Contains nautilus path"
}

test_de_specific_flatpak_filtering() {
    run_test "DE-specific flatpak filtering"
    
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/flatpaks.sh"
    
    local gnome_specific kde_specific
    
    gnome_specific=$(get_de_specific_flatpaks "gnome" "false")
    kde_specific=$(get_de_specific_flatpaks "kde" "false")
    
    assert_contains "org.gnome." "$gnome_specific" "GNOME list contains org.gnome.*"
    assert_contains "org.kde." "$kde_specific" "KDE list contains org.kde.*"
    
    # Ensure shared apps are filtered out
    if echo "$gnome_specific" | grep -q "org.mozilla.firefox"; then
        fail "GNOME list should not contain Firefox" "no Firefox" "has Firefox"
    else
        pass "GNOME list excludes shared apps like Firefox"
    fi
    
    if echo "$kde_specific" | grep -q "org.mozilla.firefox"; then
        fail "KDE list should not contain Firefox" "no Firefox" "has Firefox"
    else
        pass "KDE list excludes shared apps like Firefox"
    fi
}

main() {
    echo -e "${YELLOW}=====================================${RESET}"
    echo -e "${YELLOW}    Bluefin-Aurora Migration Tests   ${RESET}"
    echo -e "${YELLOW}=====================================${RESET}"
    
    cd "$ROOT_DIR"
    
    test_brewfile_parsing
    test_url_check
    test_flatpak_fetch
    test_variant_parsing
    test_variant_sync
    test_image_detection
    test_rpm_ostree_fallback
    test_available_targets
    test_config_path_loading
    test_de_specific_flatpak_filtering
    
    echo ""
    echo -e "${YELLOW}=====================================${RESET}"
    echo -e "${YELLOW}    Test Results                     ${RESET}"
    echo -e "${YELLOW}=====================================${RESET}"
    echo -e "  Total:  $TESTS_RUN"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${RESET}"
    echo -e "  ${RED}Failed: $TESTS_FAILED${RESET}"
    echo ""
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
