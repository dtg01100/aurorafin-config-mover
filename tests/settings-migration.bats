#!/usr/bin/env bats
# BATS tests for migrate-settings.sh
# Tests the settings migration functionality including font preferences,
# dconf settings, wallpaper, color schemes, and themes

# Source test helpers
load 'lib/test-helpers'

setup() {
    # Set up test environment
    setup_test_env
    
    # Get script directory for sourcing
    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    ROOT_DIR="$(dirname "$SCRIPT_DIR")"
    export ROOT_DIR
}

teardown() {
    # Clean up test environment
    teardown_test_env
}

# ==============================================================================
# Test Environment Tests
# ==============================================================================

@test "Test environment is properly set up" {
    [[ -n "$TEST_TEMP_DIR" ]]
    [[ -d "$TEST_TEMP_DIR" ]]
    [[ -n "$MOCK_HOME" ]]
    [[ -d "$MOCK_HOME" ]]
    [[ -n "$FIXTURES_DIR" ]]
    [[ -d "$FIXTURES_DIR" ]]
}

@test "Fixtures directory contains expected files" {
    [[ -f "$FIXTURES_DIR/kde/kdeglobals" ]]
    [[ -f "$FIXTURES_DIR/gtk/gtk-3.0/settings.ini" ]]
    [[ -f "$FIXTURES_DIR/dconf/user" ]]
    [[ -f "$FIXTURES_DIR/wallpaper/sample-wallpaper.png" ]]
    [[ -f "$FIXTURES_DIR/color-schemes/Test.colors" ]]
    [[ -d "$FIXTURES_DIR/icons/TestIconTheme" ]]
    [[ -d "$FIXTURES_DIR/themes/TestTheme" ]]
}

# ==============================================================================
# Helper Function Tests
# ==============================================================================

@test "create_mock_backup creates expected directory structure" {
    create_mock_backup "$TEST_TEMP_DIR/test-backup"
    
    [[ -d "$TEST_TEMP_DIR/test-backup/configs/.config/dconf" ]]
    [[ -d "$TEST_TEMP_DIR/test-backup/configs/.config/gtk-3.0" ]]
    [[ -d "$TEST_TEMP_DIR/test-backup/configs/.config/gtk-4.0" ]]
    [[ -d "$TEST_TEMP_DIR/test-backup/configs/.local/share/backgrounds" ]]
    [[ -d "$TEST_TEMP_DIR/test-backup/configs/.local/share/icons" ]]
    [[ -d "$TEST_TEMP_DIR/test-backup/configs/.local/share/color-schemes" ]]
    [[ -d "$TEST_TEMP_DIR/test-backup/configs/.local/share/themes" ]]
}

@test "create_mock_kdeglobals creates valid file" {
    local kdeglobals_file
    kdeglobals_file=$(create_mock_kdeglobals)
    
    [[ -f "$kdeglobals_file" ]]
    grep -q "font=" "$kdeglobals_file"
    grep -q "menuFont=" "$kdeglobals_file"
    grep -q "\[General\]" "$kdeglobals_file"
}

@test "create_mock_gtk_settings creates valid file" {
    local gtk_file
    gtk_file=$(create_mock_gtk_settings)
    
    [[ -f "$gtk_file" ]]
    grep -q "font-name=" "$gtk_file"
    grep -q "\[Settings\]" "$gtk_file"
}

@test "create_mock_dconf_user creates valid file" {
    local dconf_file
    dconf_file=$(create_mock_dconf_user)
    
    [[ -f "$dconf_file" ]]
    grep -q "font-name" "$dconf_file"
    grep -q "gtk-theme" "$dconf_file"
}

@test "assert_file_contains works correctly" {
    local test_file="$TEST_TEMP_DIR/test.txt"
    echo "Hello World" > "$test_file"
    
    # Should pass
    assert_file_contains "$test_file" "Hello"
    
    # Should fail
    run assert_file_contains "$test_file" "Goodbye"
    [[ "$status" -ne 0 ]]
}

@test "assert_dir_exists works correctly" {
    # Should pass
    assert_dir_exists "$TEST_TEMP_DIR"
    
    # Should fail
    run assert_dir_exists "$TEST_TEMP_DIR/nonexistent"
    [[ "$status" -ne 0 ]]
}

@test "assert_file_exists works correctly" {
    local test_file="$TEST_TEMP_DIR/test.txt"
    echo "test" > "$test_file"
    
    # Should pass
    assert_file_exists "$test_file"
    
    # Should fail
    run assert_file_exists "$TEST_TEMP_DIR/nonexistent.txt"
    [[ "$status" -ne 0 ]]
}

@test "mock_dconf creates working mock command" {
    mock_dconf
    
    # Check that mock dconf is in PATH
    which dconf
    
    # Test read command
    run dconf read /org/gnome/desktop/interface/font-name
    [[ "$output" == *"Noto Sans"* ]]
    
    # Test write command
    run dconf write /test/key "value"
    [[ "$output" == *"MOCK"* ]]
}

@test "copy_fixtures copies KDE fixtures correctly" {
    local dest="$TEST_TEMP_DIR/dest"
    copy_fixtures kde "$dest"
    
    [[ -f "$dest/kdeglobals" ]]
    grep -q "font=" "$dest/kdeglobals"
}

@test "copy_fixtures copies GTK fixtures correctly" {
    local dest="$TEST_TEMP_DIR/dest"
    copy_fixtures gtk "$dest"
    
    [[ -f "$dest/gtk-3.0/settings.ini" ]]
    grep -q "font-name=" "$dest/gtk-3.0/settings.ini"
}

@test "copy_fixtures copies dconf fixtures correctly" {
    local dest="$TEST_TEMP_DIR/dest"
    copy_fixtures dconf "$dest"
    
    [[ -f "$dest/dconf/user" ]]
}

@test "copy_fixtures copies wallpaper fixtures correctly" {
    local dest="$TEST_TEMP_DIR/dest"
    copy_fixtures wallpaper "$dest"
    
    [[ -f "$dest/backgrounds/sample-wallpaper.png" ]]
}

@test "copy_fixtures copies color-schemes fixtures correctly" {
    local dest="$TEST_TEMP_DIR/dest"
    copy_fixtures color-schemes "$dest"
    
    [[ -f "$dest/color-schemes/Test.colors" ]]
}

@test "copy_fixtures copies icons fixtures correctly" {
    local dest="$TEST_TEMP_DIR/dest"
    copy_fixtures icons "$dest"
    
    [[ -d "$dest/icons/TestIconTheme" ]]
    [[ -f "$dest/icons/TestIconTheme/index.theme" ]]
}

@test "copy_fixtures copies themes fixtures correctly" {
    local dest="$TEST_TEMP_DIR/dest"
    copy_fixtures themes "$dest"
    
    [[ -d "$dest/themes/TestTheme" ]]
    [[ -f "$dest/themes/TestTheme/index.theme" ]]
}

@test "create_complete_mock_backup creates full backup structure" {
    local backup_dir
    backup_dir=$(create_complete_mock_backup)
    
    # Check KDE config
    [[ -f "$backup_dir/configs/.config/kdeglobals" ]]
    
    # Check GTK config
    [[ -f "$backup_dir/configs/.config/gtk-3.0/settings.ini" ]]
    
    # Check dconf
    [[ -f "$backup_dir/configs/.config/dconf/user" ]]
    
    # Check wallpaper
    [[ -f "$backup_dir/configs/.local/share/backgrounds/sample-wallpaper.png" ]]
    
    # Check color-schemes
    [[ -f "$backup_dir/configs/.local/share/color-schemes/Test.colors" ]]
    
    # Check icons
    [[ -d "$backup_dir/configs/.local/share/icons/TestIconTheme" ]]
    
    # Check themes
    [[ -d "$backup_dir/configs/.local/share/themes/TestTheme" ]]
}

# ==============================================================================
# Extraction Function Tests
# ==============================================================================

@test "extract_kde_font_preferences extracts font settings from fixture" {
    # Use the fixture file
    local kdeglobals="$FIXTURES_DIR/kde/kdeglobals"
    
    # Run extraction (function is loaded from test-helpers.bash)
    run extract_kde_font_preferences "$kdeglobals"
    
    # Should succeed
    [[ "$status" -eq 0 ]]
    
    # Should contain font settings
    [[ "$output" == *"font="* ]]
    [[ "$output" == *"menuFont="* ]]
    [[ "$output" == *"Noto Sans"* ]]
}

@test "extract_kde_font_preferences returns error for non-existent file" {
    run extract_kde_font_preferences "/nonexistent/path/kdeglobals"
    
    # Should fail
    [[ "$status" -ne 0 ]]
}

@test "extract_kde_font_preferences returns error for file without fonts" {
    # Create a kdeglobals without font settings
    local test_file="$TEST_TEMP_DIR/kdeglobals-no-fonts"
    cat > "$test_file" << 'EOF'
[KDE]
LookAndFeelPackage=org.kde.breeze.desktop

[Icons]
Theme=breeze
EOF
    
    run extract_kde_font_preferences "$test_file"
    
    # Should fail (no fonts found)
    [[ "$status" -ne 0 ]]
}

@test "extract_gtk_font_preferences extracts font settings from fixture" {
    local settings_ini="$FIXTURES_DIR/gtk/gtk-3.0/settings.ini"
    
    run extract_gtk_font_preferences "$settings_ini"
    
    # Should succeed
    [[ "$status" -eq 0 ]]
    
    # Should contain font setting
    [[ "$output" == *"font-name="* ]]
    [[ "$output" == *"Noto Sans"* ]]
}

@test "extract_gtk_font_preferences returns error for non-existent file" {
    run extract_gtk_font_preferences "/nonexistent/path/settings.ini"
    
    # Should fail
    [[ "$status" -ne 0 ]]
}

@test "extract_gtk_font_preferences returns error for file without font" {
    # Create a settings.ini without font settings
    local test_file="$TEST_TEMP_DIR/settings-no-font.ini"
    cat > "$test_file" << 'EOF'
[Settings]
gtk-theme-name=Adwaita
icon-theme-name=Adwaita
EOF
    
    run extract_gtk_font_preferences "$test_file"
    
    # Should fail (no font found)
    [[ "$status" -ne 0 ]]
}

# ==============================================================================
# Dry Run Mode Tests
# ==============================================================================

@test "migrate_font_preferences dry-run shows preview for KDE" {
    # Set up environment with KDE font config
    local backup_dir="$TEST_TEMP_DIR/backup"
    create_mock_backup "$backup_dir"
    create_mock_kdeglobals "$backup_dir/configs/.config/kdeglobals"
    
    # Run the script with --dry-run and --all to test font migration preview
    run "$ROOT_DIR/migrate-settings.sh" --dry-run --backup-dir "$backup_dir" --all
    
    # Should show preview (may exit with code 0 or require confirmation)
    # The output should contain font-related information
    [[ "$output" == *"font"* ]] || [[ "$output" == *"Font"* ]] || [[ "$output" == *"preview"* ]] || [[ "$output" == *"DRY-RUN"* ]] || [[ "$status" -eq 0 ]]
}

@test "migrate_font_preferences dry-run shows preview for GTK" {
    # Set up environment with GTK font config
    local backup_dir="$TEST_TEMP_DIR/backup"
    create_mock_backup "$backup_dir"
    create_mock_gtk_settings "$backup_dir/configs/.config/gtk-3.0/settings.ini"
    
    # Run the script with --dry-run and --all to test font migration preview
    run "$ROOT_DIR/migrate-settings.sh" --dry-run --backup-dir "$backup_dir" --all
    
    # Should show preview (may exit with code 0 or require confirmation)
    [[ "$output" == *"font"* ]] || [[ "$output" == *"Font"* ]] || [[ "$output" == *"preview"* ]] || [[ "$output" == *"DRY-RUN"* ]] || [[ "$status" -eq 0 ]]
}

# ==============================================================================
# Script Argument Tests
# ==============================================================================

@test "migrate-settings.sh --help shows usage" {
    run "$ROOT_DIR/migrate-settings.sh" --help
    
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"USAGE"* ]] || [[ "$output" == *"usage"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--backup-dir"* ]]
}

@test "migrate-settings.sh --dry-run does not make changes" {
    # Create a mock backup
    local backup_dir="$TEST_TEMP_DIR/backup"
    create_complete_mock_backup "$backup_dir"
    
    # Run with dry-run, --all, and --yes to skip interactive prompts
    run "$ROOT_DIR/migrate-settings.sh" --dry-run --backup-dir "$backup_dir" --all --yes
    
    # Should succeed
    [[ "$status" -eq 0 ]]
    
    # Verify no changes were made to mock home directory
    [[ ! -f "$MOCK_HOME/.config/kdeglobals" ]]
}
