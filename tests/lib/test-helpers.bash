#!/bin/bash
# Test helper functions for migrate-settings.sh tests
# This file should be sourced by BATS test files

# Get the root directory of the project
get_root_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    dirname "$(dirname "$script_dir")"
}

# Set up test environment
# Creates temporary directories and sets environment variables
# Usage: setup_test_env
setup_test_env() {
    ROOT_DIR="$(get_root_dir)"
    export ROOT_DIR
    
    # Create a unique temp directory for this test
    TEST_TEMP_DIR=$(mktemp -d)
    export TEST_TEMP_DIR
    
    # Set up mock HOME directory
    export MOCK_HOME="$TEST_TEMP_DIR/home"
    mkdir -p "$MOCK_HOME/.config"
    mkdir -p "$MOCK_HOME/.local/share"
    
    # Set up mock backup directory
    export MOCK_BACKUP_DIR="$TEST_TEMP_DIR/backup"
    mkdir -p "$MOCK_BACKUP_DIR"
    
    # Point to fixtures directory
    export FIXTURES_DIR="$ROOT_DIR/tests/fixtures"
    
    # Disable actual dconf operations by default
    export MOCK_DCONF=true
    
    # Default to dry-run mode for safety
    export DRY_RUN=true
}

# Tear down test environment
# Cleans up temporary directories
# Usage: teardown_test_env
teardown_test_env() {
    if [[ -n "${TEST_TEMP_DIR:-}" && -d "${TEST_TEMP_DIR:-}" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Create a mock backup directory structure
# Usage: create_mock_backup [base_dir]
# If base_dir is not provided, uses MOCK_BACKUP_DIR
create_mock_backup() {
    local base_dir="${1:-$MOCK_BACKUP_DIR}"
    
    # Create directory structure
    mkdir -p "$base_dir/configs/.config/dconf"
    mkdir -p "$base_dir/configs/.config/gtk-3.0"
    mkdir -p "$base_dir/configs/.config/gtk-4.0"
    mkdir -p "$base_dir/configs/.config/plasma"
    mkdir -p "$base_dir/configs/.local/share/backgrounds"
    mkdir -p "$base_dir/configs/.local/share/icons"
    mkdir -p "$base_dir/configs/.local/share/color-schemes"
    mkdir -p "$base_dir/configs/.local/share/themes"
    mkdir -p "$base_dir/configs/.local/share/cursors"
    mkdir -p "$base_dir/logs"
    
    echo "$base_dir"
}

# Create mock kdeglobals file
# Usage: create_mock_kdeglobals [destination_file]
create_mock_kdeglobals() {
    local dest="${1:-$MOCK_BACKUP_DIR/configs/.config/kdeglobals}"
    mkdir -p "$(dirname "$dest")"
    
    cat > "$dest" << 'EOF'
[General]
font=Noto Sans,10,-1,5,50,0,0,0,0,0
menuFont=Noto Sans,10,-1,5,50,0,0,0,0,0
toolBarFont=Noto Sans,10,-1,5,50,0,0,0,0,0
desktopFont=Noto Sans,10,-1,5,50,0,0,0,0,0
fixed=Noto Mono,10,-1,5,50,0,0,0,0,0

[KDE]
LookAndFeelPackage=org.kde.breeze.desktop

[Icons]
Theme=breeze
EOF
    
    echo "$dest"
}

# Create mock GTK settings.ini file
# Usage: create_mock_gtk_settings [destination_file]
create_mock_gtk_settings() {
    local dest="${1:-$MOCK_BACKUP_DIR/configs/.config/gtk-3.0/settings.ini}"
    mkdir -p "$(dirname "$dest")"
    
    cat > "$dest" << 'EOF'
[Settings]
font-name=Noto Sans 10
gtk-theme-name=Adwaita
icon-theme-name=Adwaita
cursor-theme-name=Adwaita
EOF
    
    echo "$dest"
}

# Create mock dconf user file
# Usage: create_mock_dconf_user [destination_file]
create_mock_dconf_user() {
    local dest="${1:-$MOCK_BACKUP_DIR/configs/.config/dconf/user}"
    mkdir -p "$(dirname "$dest")"
    
    # Create dconf dump format (INI-like output from 'dconf dump /')
    cat > "$dest" << 'EOF'
[org/gnome/desktop/interface]
font-name='Noto Sans 10'
monospace-font-name='Noto Mono 10'
gtk-theme='Adwaita'
icon-theme='Adwaita'
cursor-theme='Adwaita'
cursor-size=24

[org/gnome/desktop/background]
picture-uri='file:///home/testuser/.local/share/backgrounds/wallpaper.png'
EOF
    
    echo "$dest"
}

# Assert that a file contains expected content
# Usage: assert_file_contains file_path expected_content
assert_file_contains() {
    local file="$1"
    local expected="$2"
    
    if [[ ! -f "$file" ]]; then
        echo "FAIL: File does not exist: $file" >&2
        return 1
    fi
    
    if ! grep -q "$expected" "$file"; then
        echo "FAIL: File '$file' does not contain expected content: $expected" >&2
        echo "File contents:" >&2
        cat "$file" >&2
        return 1
    fi
    
    return 0
}

# Assert that a directory exists
# Usage: assert_dir_exists dir_path
assert_dir_exists() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        echo "FAIL: Directory does not exist: $dir" >&2
        return 1
    fi
    
    return 0
}

# Assert that a file exists
# Usage: assert_file_exists file_path
assert_file_exists() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        echo "FAIL: File does not exist: $file" >&2
        return 1
    fi
    
    return 0
}

# Mock the dconf command for testing
# Creates a mock dconf script in PATH
# Usage: mock_dconf
mock_dconf() {
    local mock_bin="$TEST_TEMP_DIR/bin"
    mkdir -p "$mock_bin"
    
    cat > "$mock_bin/dconf" << 'EOF'
#!/bin/bash
# Mock dconf command for testing

case "${1:-}" in
    write)
        echo "MOCK: dconf write $2 = $3"
        ;;
    read)
        case "$2" in
            /org/gnome/desktop/interface/font-name)
                echo "'Noto Sans 10'"
                ;;
            /org/gnome/desktop/interface/gtk-theme)
                echo "'Adwaita'"
                ;;
            *)
                echo "mock-value"
                ;;
        esac
        ;;
    dump)
        # Output in dconf dump format (INI-like)
        echo "[org/gnome/desktop/interface]"
        echo "font-name='Noto Sans 10'"
        echo "monospace-font-name='Noto Mono 10'"
        echo "gtk-theme='Adwaita'"
        echo "icon-theme='Adwaita'"
        echo "cursor-theme='Adwaita'"
        echo "cursor-size=24"
        echo ""
        echo "[org/gnome/desktop/background]"
        echo "picture-uri='file:///home/testuser/.local/share/backgrounds/wallpaper.png'"
        ;;
    load)
        echo "MOCK: dconf load $2"
        ;;
    *)
        echo "Unknown dconf command: $1" >&2
        exit 1
        ;;
esac
EOF
    chmod +x "$mock_bin/dconf"
    
    # Prepend mock bin to PATH
    export PATH="$mock_bin:$PATH"
}

# Skip test if running as root
# Usage: skip_if_root
skip_if_root() {
    if [[ $EUID -eq 0 ]]; then
        echo "SKIP: Test cannot run as root"
        return 1
    fi
    return 0
}

# Copy fixtures to a destination directory
# Usage: copy_fixtures fixture_type destination
# fixture_type can be: kde, gtk, dconf, wallpaper, color-schemes, icons, themes
copy_fixtures() {
    local fixture_type="$1"
    local dest="$2"
    
    case "$fixture_type" in
        kde)
            mkdir -p "$dest"
            cp "$FIXTURES_DIR/kde/kdeglobals" "$dest/"
            ;;
        gtk)
            mkdir -p "$dest/gtk-3.0"
            cp "$FIXTURES_DIR/gtk/gtk-3.0/settings.ini" "$dest/gtk-3.0/"
            ;;
        dconf)
            mkdir -p "$dest/dconf"
            cp "$FIXTURES_DIR/dconf/user" "$dest/dconf/"
            ;;
        wallpaper)
            mkdir -p "$dest/backgrounds"
            cp "$FIXTURES_DIR/wallpaper/sample-wallpaper.png" "$dest/backgrounds/"
            ;;
        color-schemes)
            mkdir -p "$dest/color-schemes"
            cp "$FIXTURES_DIR/color-schemes/Test.colors" "$dest/color-schemes/"
            ;;
        icons)
            mkdir -p "$dest/icons"
            cp -r "$FIXTURES_DIR/icons/TestIconTheme" "$dest/icons/"
            ;;
        themes)
            mkdir -p "$dest/themes"
            cp -r "$FIXTURES_DIR/themes/TestTheme" "$dest/themes/"
            ;;
        all)
            copy_fixtures kde "$dest/.config"
            copy_fixtures gtk "$dest/.config"
            copy_fixtures dconf "$dest/.config"
            copy_fixtures wallpaper "$dest/.local/share"
            copy_fixtures color-schemes "$dest/.local/share"
            copy_fixtures icons "$dest/.local/share"
            copy_fixtures themes "$dest/.local/share"
            ;;
        *)
            echo "Unknown fixture type: $fixture_type" >&2
            return 1
            ;;
    esac
    
    return 0
}

# Create a complete mock backup with all fixtures
# Usage: create_complete_mock_backup [base_dir]
create_complete_mock_backup() {
    local base_dir="${1:-$MOCK_BACKUP_DIR}"
    local configs_dir="$base_dir/configs"
    
    mkdir -p "$configs_dir"
    mkdir -p "$base_dir/logs"
    copy_fixtures all "$configs_dir"
    
    echo "$base_dir"
}

# ==============================================================================
# Functions extracted from migrate-settings.sh for testing
# These are copies of the functions to allow testing without triggering main()
# ==============================================================================

# Helper function to extract font preferences from kdeglobals
# Extracted from migrate-settings.sh for testing
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
# Extracted from migrate-settings.sh for testing
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
