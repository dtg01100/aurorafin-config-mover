#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$ROOT_DIR/data"

BLUEFIN_JUSTFILE_URL="https://raw.githubusercontent.com/ublue-os/bluefin/main/Justfile"
AURORA_JUSTFILE_URL="https://raw.githubusercontent.com/ublue-os/aurora/main/Justfile"

CACHE_FILE="$DATA_DIR/variants-cache.json"
CACHE_EXPIRY_SECONDS=$((24 * 60 * 60))

fetch_justfile() {
    local url="$1"
    curl -sL "$url" 2>/dev/null || echo ""
}

parse_flavors() {
    local content="$1"
    
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
                local flavor="${BASH_REMATCH[1]}"
                flavors+=("$flavor")
            fi
        fi
    done <<< "$content"
    
    printf '%s\n' "${flavors[@]}"
}

parse_tags() {
    local content="$1"
    
    local in_tags=false
    local tags=()
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^tags.*= ]]; then
            in_tags=true
            continue
        fi
        
        if [[ "$in_tags" == "true" ]]; then
            if [[ "$line" == ")"* ]]; then
                break
            fi
            
            if [[ "$line" =~ \[([^\]]+)\]= ]]; then
                local tag="${BASH_REMATCH[1]}"
                tags+=("$tag")
            fi
        fi
    done <<< "$content"
    
    printf '%s\n' "${tags[@]}"
}

parse_images() {
    local content="$1"
    
    local images=()
    
    while IFS= read -r line; do
        if [[ "$line" =~ \[bluefin([^\]]*)\]=bluefin([^\]]*) ]]; then
            local src="${BASH_REMATCH[1]}"
            local dst="${BASH_REMATCH[2]}"
            if [[ -n "$src" ]]; then
                images+=("bluefin$src")
            fi
        fi
        if [[ "$line" =~ \[aurora([^\]]*)\]=aurora([^\]]*) ]]; then
            local src="${BASH_REMATCH[1]}"
            local dst="${BASH_REMATCH[2]}"
            if [[ -n "$src" ]]; then
                images+=("aurora$src")
            fi
        fi
    done <<< "$content"
    
    if [[ ${#images[@]} -eq 0 ]]; then
        images=("bluefin" "bluefin-dx" "aurora" "aurora-dx")
    fi
    
    printf '%s\n' "${images[@]}" | sort -u
}

build_image_list() {
    local family="$1"
    local flavors="$2"
    local tags="$3"
    local base_images="$4"
    
    local images=()
    
    while IFS= read -r base; do
        [[ -z "$base" ]] && continue
        
        if [[ ! "$base" =~ ^$family ]]; then
            continue
        fi
        
        while IFS= read -r flavor; do
            [[ -z "$flavor" ]] && continue
            
            local image_name="$base"
            if [[ "$flavor" != "main" ]]; then
                image_name="$base-$flavor"
            fi
            
            while IFS= read -r tag; do
                [[ -z "$tag" ]] && continue
                images+=("ghcr.io/ublue-os/${image_name}:${tag}")
            done <<< "$tags"
        done <<< "$flavors"
    done <<< "$base_images"
    
    printf '%s\n' "${images[@]}" | sort -u
}

sync_variants() {
    local force="${1:-false}"
    
    local cache_age=0
    if [[ -f "$CACHE_FILE" ]]; then
        cache_age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
        
        if [[ "$force" != "true" && $cache_age -lt $CACHE_EXPIRY_SECONDS ]]; then
            echo "Using cached variants (age: ${cache_age}s)"
            cat "$CACHE_FILE"
            return 0
        fi
    fi
    
    echo "Fetching variants from upstream..."
    
    mkdir -p "$DATA_DIR"
    
    local bluefin_justfile aurora_justfile
    bluefin_justfile=$(fetch_justfile "$BLUEFIN_JUSTFILE_URL")
    aurora_justfile=$(fetch_justfile "$AURORA_JUSTFILE_URL")
    
    if [[ -z "$bluefin_justfile" || -z "$aurora_justfile" ]]; then
        if [[ -f "$CACHE_FILE" ]]; then
            echo "Fetch failed, using stale cache"
            cat "$CACHE_FILE"
            return 0
        fi
        echo "ERROR: Failed to fetch Justfiles" >&2
        return 1
    fi
    
    local bluefin_flavors aurora_flavors
    bluefin_flavors=$(parse_flavors "$bluefin_justfile")
    aurora_flavors=$(parse_flavors "$aurora_justfile")
    
    local bluefin_tags aurora_tags
    bluefin_tags=$(parse_tags "$bluefin_justfile")
    aurora_tags=$(parse_tags "$aurora_justfile")
    
    local bluefin_images aurora_images
    bluefin_images=$(parse_images "$bluefin_justfile")
    aurora_images=$(parse_images "$aurora_justfile")
    
    local bluefin_list aurora_list
    bluefin_list=$(build_image_list "bluefin" "$bluefin_flavors" "$bluefin_tags" "$bluefin_images")
    aurora_list=$(build_image_list "aurora" "$aurora_flavors" "$aurora_tags" "$aurora_images")
    
    local timestamp
    timestamp=$(date -Iseconds)
    
    cat > "$CACHE_FILE" << EOF
{
  "timestamp": "$timestamp",
  "bluefin": {
    "flavors": [$(echo "$bluefin_flavors" | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')],
    "tags": [$(echo "$bluefin_tags" | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')],
    "images": [$(echo "$bluefin_list" | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')]
  },
  "aurora": {
    "flavors": [$(echo "$aurora_flavors" | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')],
    "tags": [$(echo "$aurora_tags" | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')],
    "images": [$(echo "$aurora_list" | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//')]
  }
}
EOF
    
    echo "Synced variants at $timestamp"
    cat "$CACHE_FILE"
}

get_available_images() {
    local family="$1"
    
    if [[ ! -f "$CACHE_FILE" ]]; then
        sync_variants >/dev/null || return 1
    fi
    
    jq -r ".$family.images[]" "$CACHE_FILE" 2>/dev/null
}

get_available_tags() {
    local family="$1"
    
    if [[ ! -f "$CACHE_FILE" ]]; then
        sync_variants >/dev/null || return 1
    fi
    
    jq -r ".$family.tags[]" "$CACHE_FILE" 2>/dev/null
}

get_available_flavors() {
    local family="$1"
    
    if [[ ! -f "$CACHE_FILE" ]]; then
        sync_variants >/dev/null || return 1
    fi
    
    jq -r ".$family.flavors[]" "$CACHE_FILE" 2>/dev/null
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
    local force="${1:-false}"
    
    sync_variants "$force"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "${1:-false}"
fi
