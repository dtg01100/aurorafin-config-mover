#!/bin/bash
set -euo pipefail

SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="bluefin-aurora-migrate"  # Used in help output

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

DRY_RUN=false
VERBOSE=false
YES_MODE=false
BACKUP_DIR=""

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)  echo -e "${timestamp} [INFO]  $message" ;;
        WARN)  echo -e "${YELLOW}${timestamp} [WARN]  $message${RESET}" ;;
        ERROR) echo -e "${RED}${timestamp} [ERROR] $message${RESET}" ;;
        DEBUG) [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}${timestamp} [DEBUG] $message${RESET}" ;;
    esac
    
    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        echo "${timestamp} [${level}] ${message}" >> "$BACKUP_DIR/logs/migration.log"
    fi
}

info()  { log "INFO" "$@"; }
warn()  { log "WARN" "$@"; }
error() { log "ERROR" "$@"; exit 1; }
debug() { log "DEBUG" "$@"; }

print_header() {
    local title="$1"
    local width=64
    local padding=$(( (width - ${#title}) / 2 ))
    
    echo ""
    echo -e "${CYAN}$(printf '═%.0s' $(seq 1 $width))${RESET}"
    echo -e "${CYAN}║${RESET}${BOLD}$(printf ' %.0s' $(seq 1 $padding))${title}$(printf ' %.0s' $(seq 1 $((width - padding - ${#title}))))${RESET}${CYAN}║${RESET}"
    echo -e "${CYAN}$(printf '═%.0s' $(seq 1 $width))${RESET}"
    echo ""
}

print_section() {
    local title="$1"
    echo ""
    echo -e "${BLUE}─────────────────────────────────────────────────────────────────${RESET}"
    echo -e "${BOLD}${title}${RESET}"
    echo -e "${BLUE}─────────────────────────────────────────────────────────────────${RESET}"
}

print_success() { echo -e "${GREEN}✓${RESET} $*"; }
print_warning() { echo -e "${YELLOW}⚠${RESET} $*"; }
print_error()   { echo -e "${RED}✗${RESET} $*"; }

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [[ "$YES_MODE" == "true" ]]; then
        return 0
    fi
    
    local choices
    case "$default" in
        y|Y) choices="[Y/n]" ;;
        n|N) choices="[y/N]" ;;
        *)   choices="[y/n]" ;;
    esac
    
    echo -en "${BOLD}${prompt}${RESET} ${choices}: "
    read -r response
    
    case "$response" in
        y|Y|yes|YES) return 0 ;;
        n|N|no|NO)   return 1 ;;
        "")          [[ "$default" == "y" || "$default" == "Y" ]] && return 0 || return 1 ;;
        *)           return 1 ;;
    esac
}

generate_timestamp() {
    date '+%Y%m%d-%H%M%S'
}

get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [[ -L "$source" ]]; do
        local dir
        dir=$(cd -P "$(dirname "$source")" && pwd)
        source=$(readlink "$source")
        [[ "$source" != /* ]] && source="$dir/$source"
    done
    cd -P "$(dirname "$source")" && pwd
}

check_dependencies() {
    local missing=()
    local deps=("bootc" "jq" "basename" "dirname" "mkdir" "cp" "mv" "rm")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing[*]}"
    fi
}

display_unsupported_warning() {
    local acknowledged=false
    
    while [[ "$acknowledged" == "false" ]]; do
        echo ""
        warn "WARNING: UNSUPPORTED TOOL"
        echo ""
        echo -e "This tool is not affiliated with, endorsed by, or supported by either the"
        echo -e "${BOLD}Bluefin${RESET} or ${BOLD}Aurora${RESET} projects. It is a community-made utility and comes with"
        echo -e "no guarantees."
        echo ""
        echo -e "Please acknowledge that you understand this is unsupported:"
        echo -en "Type ${GREEN}\"yes\"${RESET} to continue: "
        read -r response
        
        case "${response,,}" in
            yes)
                acknowledged=true
                info "Acknowledged. Continuing..."
                ;;
            *)
                echo ""
                warn "You must type 'yes' to acknowledge this warning."
                echo ""
                ;;
        esac
    done
}

run_cmd() {
    local cmd="$*"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} Would run: $cmd"
        return 0
    fi
    
    debug "Running: $cmd"
    eval "$cmd"
}

backup_path() {
    local src="$1"
    local dest_dir="$2"
    
    if [[ ! -e "$src" ]]; then
        debug "Path does not exist, skipping: $src"
        return 0
    fi
    
    local rel_path="${src#"$HOME"/}"
    local dest="$dest_dir/$rel_path"
    local dest_parent
    dest_parent=$(dirname "$dest")
    
    run_cmd "mkdir -p '$dest_parent'"
    run_cmd "cp -a '$src' '$dest'"
    
    info "Backed up: $src"
}

archive_path() {
    local src="$1"
    local dest_dir="$2"
    
    if [[ ! -e "$src" ]]; then
        debug "Path does not exist, skipping: $src"
        return 0
    fi
    
    local rel_path="${src#"$HOME"/}"
    local dest="$dest_dir/$rel_path"
    local dest_parent
    dest_parent=$(dirname "$dest")
    
    run_cmd "mkdir -p '$dest_parent'"
    run_cmd "mv '$src' '$dest'"
    
    info "Archived: $src -> $dest"
}

remove_path() {
    local src="$1"
    
    if [[ ! -e "$src" ]]; then
        debug "Path does not exist, skipping: $src"
        return 0
    fi
    
    run_cmd "rm -rf '$src'"
    info "Removed: $src"
}

create_backup_dir() {
    local base_name="${1:-config-migration-backup}"
    local timestamp
    timestamp=$(generate_timestamp)
    
    BACKUP_DIR="$HOME/${base_name}-${timestamp}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} Would create: $BACKUP_DIR"
        return 0
    fi
    
    mkdir -p "$BACKUP_DIR/logs"
    mkdir -p "$BACKUP_DIR/configs"
    
    echo "$BACKUP_DIR"
}

write_manifest() {
    local manifest_file="$BACKUP_DIR/manifest.json"
    local timestamp
    timestamp=$(date -Iseconds)
    
    cat > "$manifest_file" << EOF
{
  "version": "$SCRIPT_VERSION",
  "timestamp": "$timestamp",
  "backup_dir": "$BACKUP_DIR",
  "source_image": "${SOURCE_IMAGE:-unknown}",
  "target_image": "${TARGET_IMAGE:-unknown}",
  "source_de": "${SOURCE_DE:-unknown}",
  "target_de": "${TARGET_DE:-unknown}"
}
EOF
    
    info "Manifest written to: $manifest_file"
}

show_help() {
    cat << EOF
${BOLD}Bluefin-Aurora Migration Tool v${SCRIPT_VERSION}${RESET}

${BOLD}USAGE${RESET}
    $0 [OPTIONS]

${BOLD}OPTIONS${RESET}
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -y, --yes           Skip all confirmations
    --dry-run           Show what would happen without making changes
    --restore <dir>     Restore from a backup directory

${BOLD}EXAMPLES${RESET}
    $0 --dry-run        Preview migration
    $0 -y               Run without prompts
    $0 --restore ~/config-migration-backup-20260215-120000

EOF
}

parse_common_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
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
            *)
                shift
                ;;
        esac
    done
}
