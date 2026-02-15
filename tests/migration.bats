#!/usr/bin/env bats

setup() {
    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    ROOT_DIR="$(dirname "$SCRIPT_DIR")"
    export ROOT_DIR
    export PATH="$ROOT_DIR/scripts:$PATH"
}

@test "Brewfile parsing extracts flatpak IDs" {
    sample='flatpak "org.gnome.Nautilus"
flatpak "org.gnome.Terminal"
# comment
flatpak "org.mozilla.firefox"'
    
    result=$(echo "$sample" | grep -E '^flatpak "' | sed 's/flatpak "\([^"]*\)"/\1/' | sort -u)
    
    [[ "$result" == *"org.gnome.Nautilus"* ]]
    [[ "$result" == *"org.gnome.Terminal"* ]]
    [[ "$result" == *"org.mozilla.firefox"* ]]
}

@test "Bluefin Brewfile URL is accessible" {
    url="https://raw.githubusercontent.com/projectbluefin/common/main/system_files/bluefin/usr/share/ublue-os/homebrew/system-flatpaks.Brewfile"
    response=$(curl -sL -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    [[ "$response" == "200" ]]
}

@test "Aurora Brewfile URL is accessible" {
    url="https://raw.githubusercontent.com/get-aurora-dev/common/main/system_files/shared/usr/share/ublue-os/homebrew/system-flatpaks.Brewfile"
    response=$(curl -sL -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    [[ "$response" == "200" ]]
}

@test "get_de_flatpaks returns GNOME flatpaks" {
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/flatpaks.sh"
    
    flatpaks=$(get_de_flatpaks "gnome")
    
    [[ -n "$flatpaks" ]]
    [[ "$flatpaks" == *"org.gnome.Nautilus"* ]]
    [[ "$flatpaks" == *"org.gnome.Calculator"* ]]
}

@test "get_de_flatpaks returns KDE flatpaks" {
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/flatpaks.sh"
    
    flatpaks=$(get_de_flatpaks "kde")
    
    [[ -n "$flatpaks" ]]
    [[ "$flatpaks" == *"org.kde.okular"* ]]
    [[ "$flatpaks" == *"org.kde.gwenview"* ]]
}

@test "get_de_specific_flatpaks filters to DE-specific apps" {
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/flatpaks.sh"
    
    gnome=$(get_de_specific_flatpaks "gnome" "false")
    kde=$(get_de_specific_flatpaks "kde" "false")
    
    # GNOME should contain org.gnome.* apps
    [[ "$gnome" == *"org.gnome."* ]]
    
    # KDE should contain org.kde.* apps
    [[ "$kde" == *"org.kde."* ]]
    
    # Shared apps should be filtered out
    [[ "$gnome" != *"org.mozilla.firefox"* ]]
    [[ "$kde" != *"org.mozilla.firefox"* ]]
}

@test "parse flavors from Justfile" {
    sample='flavors := '"'"'(
    [main]=main
    [nvidia-open]=nvidia-open
)'
    
    flavors=$(echo "$sample" | grep -E '^\s*\[' | sed 's/.*\[\([^]]*\)\].*/\1/')
    
    [[ "$flavors" == *"main"* ]]
    [[ "$flavors" == *"nvidia-open"* ]]
}

@test "variant sync creates cache file" {
    chmod +x "$ROOT_DIR/scripts/sync-variants.sh"
    
    # Remove old cache
    rm -f "$ROOT_DIR/data/variants-cache.json"
    
    # Run sync (suppress output)
    "$ROOT_DIR/scripts/sync-variants.sh" >/dev/null 2>&1 || true
    
    # Check cache exists
    [[ -f "$ROOT_DIR/data/variants-cache.json" ]]
    
    # Check cache contents
    cache=$(cat "$ROOT_DIR/data/variants-cache.json")
    [[ "$cache" == *'"bluefin"'* ]]
    [[ "$cache" == *'"aurora"'* ]]
    [[ "$cache" == *'"flavors"'* ]]
    [[ "$cache" == *'"tags"'* ]]
    [[ "$cache" == *'"images"'* ]]
}

@test "detect image from mock bootc status" {
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/detect.sh"
    
    MOCK_BOOTC="ghcr.io/ublue-os/bluefin-dx:stable"
    
    status=$(get_bootc_status)
    image=$(echo "$status" | jq -r '.status.booted.image.name')
    
    [[ "$image" == "ghcr.io/ublue-os/bluefin-dx:stable" ]]
}

@test "detect_current_image sets all variables" {
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/detect.sh"
    
    MOCK_BOOTC="ghcr.io/ublue-os/bluefin-dx:stable"
    detect_current_image
    
    [[ "$SOURCE_FAMILY" == "bluefin" ]]
    [[ "$SOURCE_DE" == "gnome" ]]
    [[ "$SOURCE_VARIANT" == "dx" ]]
    [[ "$SOURCE_TAG" == "stable" ]]
}

@test "detect aurora image correctly" {
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/detect.sh"
    
    MOCK_BOOTC="ghcr.io/ublue-os/aurora-dx:latest"
    detect_current_image
    
    [[ "$SOURCE_FAMILY" == "aurora" ]]
    [[ "$SOURCE_DE" == "kde" ]]
    [[ "$SOURCE_VARIANT" == "dx" ]]
    [[ "$SOURCE_TAG" == "latest" ]]
}

@test "get_target_family returns opposite family" {
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/detect.sh"
    
    SOURCE_FAMILY="bluefin"
    target=$(get_target_family)
    [[ "$target" == "aurora" ]]
    
    SOURCE_FAMILY="aurora"
    target=$(get_target_family)
    [[ "$target" == "bluefin" ]]
}

@test "get_target_de returns opposite DE" {
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/detect.sh"
    
    SOURCE_DE="gnome"
    target=$(get_target_de)
    [[ "$target" == "kde" ]]
    
    SOURCE_DE="kde"
    target=$(get_target_de)
    [[ "$target" == "gnome" ]]
}

@test "get_available_targets returns matching variants" {
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/detect.sh"
    
    MOCK_BOOTC="ghcr.io/ublue-os/bluefin-dx:stable"
    detect_current_image
    
    targets=$(get_available_targets "$SOURCE_FAMILY" "$SOURCE_VARIANT" "$SOURCE_TAG")
    
    [[ -n "$targets" ]]
    [[ "$targets" == *"aurora-dx:stable"* ]]
}

@test "build_target_image constructs correct image name" {
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/detect.sh"
    
    image=$(build_target_image "aurora" "dx" "stable")
    [[ "$image" == "ghcr.io/ublue-os/aurora-dx:stable" ]]
    
    image=$(build_target_image "bluefin" "nvidia-open" "latest")
    [[ "$image" == "ghcr.io/ublue-os/bluefin-nvidia-open:latest" ]]
    
    image=$(build_target_image "aurora" "" "beta")
    [[ "$image" == "ghcr.io/ublue-os/aurora:beta" ]]
}

@test "GNOME config paths file has content" {
    [[ -f "$ROOT_DIR/configs/gnome-paths.txt" ]]
    
    count=$(wc -l < "$ROOT_DIR/configs/gnome-paths.txt")
    [[ $count -gt 50 ]]
    
    # Check for key paths
    content=$(cat "$ROOT_DIR/configs/gnome-paths.txt")
    [[ "$content" == *".config/gnome-shell"* ]]
    [[ "$content" == *".config/nautilus"* ]]
    [[ "$content" == *".config/dconf"* ]]
}

@test "KDE config paths file has content" {
    [[ -f "$ROOT_DIR/configs/kde-paths.txt" ]]
    
    count=$(wc -l < "$ROOT_DIR/configs/kde-paths.txt")
    [[ $count -gt 50 ]]
    
    # Check for key paths
    content=$(cat "$ROOT_DIR/configs/kde-paths.txt")
    [[ "$content" == *".config/plasma"* ]]
    [[ "$content" == *".config/kwin"* ]]
    [[ "$content" == *".config/kdeglobals"* ]]
}

@test "load_config_paths returns absolute paths" {
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/archive.sh"
    
    paths=$(load_config_paths "gnome" 2>/dev/null || echo "")
    
    [[ -n "$paths" ]]
    [[ "$paths" == *"$HOME/.config/gnome-shell"* ]] || [[ "$paths" == *"$HOME/.config/nautilus"* ]]
}

@test "is_flatpak_installed works correctly" {
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/flatpaks.sh"
    
    if command -v flatpak &>/dev/null; then
        installed=$(flatpak list --app --columns=application 2>/dev/null | head -1)
        if [[ -n "$installed" ]]; then
            is_flatpak_installed "$installed"
            [[ $? -eq 0 ]]
        fi
        
        # Test with a flatpak that should NOT exist (use ! for negative test)
        ! is_flatpak_installed "com.nonexistent.app.12345"
    else
        skip "flatpak not installed"
    fi
}

@test "shellcheck passes on all shell scripts" {
    if command -v shellcheck &>/dev/null; then
        # Run from project root
        cd "$ROOT_DIR"
        
        # Run shellcheck and capture output
        output=$(shellcheck -x -e SC1091,SC2034,SC2153,SC2155 scripts/*.sh lib/*.sh migrate-pre.sh migrate-post.sh 2>&1)
        
        # Check if there are any errors (shellcheck returns non-zero if errors found)
        if [[ -n "$output" ]]; then
            echo "$output" | head -5
        fi
        
        # Return code 0 means no issues, anything else is a problem
        shellcheck -x -e SC1091,SC2034,SC2153,SC2155 scripts/*.sh lib/*.sh migrate-pre.sh migrate-post.sh >/dev/null 2>&1
    else
        skip "shellcheck not installed"
    fi
}

@test "migrate-pre.sh --help shows usage" {
    output=$("$ROOT_DIR/migrate-pre.sh" --help)
    
    [[ "$output" == *"USAGE"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--target"* ]]
}

@test "migrate-post.sh --help shows usage" {
    output=$("$ROOT_DIR/migrate-post.sh" --help)
    
    [[ "$output" == *"USAGE"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--restore"* ]]
}
