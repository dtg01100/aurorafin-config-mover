#!/bin/bash
set -euo pipefail

SOURCE_IMAGE=""
SOURCE_FAMILY=""
SOURCE_DE=""
SOURCE_VARIANT=""
SOURCE_TAG=""

TARGET_IMAGE=""
TARGET_FAMILY=""
TARGET_DE=""
TARGET_VARIANT=""
TARGET_TAG=""

declare -A DESKTOP_MAP=(
    ["bluefin"]="gnome"
    ["aurora"]="kde"
)

VARIANTS_CACHE_FILE=""

get_bootc_status() {
    if [[ -n "${MOCK_BOOTC:-}" ]]; then
        local tag="stable"
        if [[ "$MOCK_BOOTC" == *":"* ]]; then
            tag="${MOCK_BOOTC##*:}"
        fi
        echo "{\"status\":{\"booted\":{\"image\":{\"name\":\"$MOCK_BOOTC\",\"tag\":\"$tag\"}}}}"
        return
    fi
    
    local bootc_output=""
    
    if command -v bootc &>/dev/null; then
        bootc_output=$(bootc status --json 2>/dev/null || echo "")
    fi
    
    if [[ -n "$bootc_output" && "$bootc_output" != "{}" ]]; then
        echo "$bootc_output"
        return
    fi
    
    if command -v rpm-ostree &>/dev/null; then
        local booted_image
        booted_image=$(rpm-ostree status --json 2>/dev/null | jq -r '.deployments[0]["container-image-reference"] // empty' | sed 's|^ostree-image-signed:docker://||')
        
        if [[ -n "$booted_image" ]]; then
            local tag="stable"
            if [[ "$booted_image" == *":"* ]]; then
                tag="${booted_image##*:}"
            fi
            echo "{\"status\":{\"booted\":{\"image\":{\"name\":\"$booted_image\",\"tag\":\"$tag\"}}}}"
            return
        fi
    fi
    
    echo "{}"
}

detect_current_image() {
    local status
    status=$(get_bootc_status)
    
    SOURCE_IMAGE=$(echo "$status" | jq -r '.status.booted.image.name // empty')
    
    if [[ -z "$SOURCE_IMAGE" ]]; then
        error "Could not detect current image. Are you running on Bluefin or Aurora?"
    fi
    
    local image_name
    image_name=$(basename "$SOURCE_IMAGE")
    
    if [[ "$SOURCE_IMAGE" == *"bluefin"* ]]; then
        SOURCE_FAMILY="bluefin"
        SOURCE_DE="gnome"
    elif [[ "$SOURCE_IMAGE" == *"aurora"* ]]; then
        SOURCE_FAMILY="aurora"
        SOURCE_DE="kde"
    else
        error "Unknown image family: $SOURCE_IMAGE"
    fi
    
    if [[ "$SOURCE_IMAGE" == *"-dx"* ]]; then
        SOURCE_VARIANT="dx"
    elif [[ "$SOURCE_IMAGE" == *"-nvidia-open"* ]]; then
        SOURCE_VARIANT="nvidia-open"
    elif [[ "$SOURCE_IMAGE" == *"-nvidia"* ]]; then
        SOURCE_VARIANT="nvidia"
    elif [[ "$SOURCE_IMAGE" == *"-asus"* ]]; then
        SOURCE_VARIANT="asus"
    else
        SOURCE_VARIANT=""
    fi
    
    SOURCE_TAG=$(echo "$status" | jq -r '.status.booted.image.tag // "stable"')
    if [[ -z "$SOURCE_TAG" ]]; then
        SOURCE_TAG="stable"
    fi
    
    debug "Detected: $SOURCE_FAMILY ($SOURCE_DE), variant=$SOURCE_VARIANT, tag=$SOURCE_TAG"
}

get_target_family() {
    case "$SOURCE_FAMILY" in
        bluefin) echo "aurora" ;;
        aurora)  echo "bluefin" ;;
        *)       echo "" ;;
    esac
}

get_target_de() {
    case "$SOURCE_DE" in
        gnome) echo "kde" ;;
        kde)   echo "gnome" ;;
        *)     echo "" ;;
    esac
}

build_target_image() {
    local family="$1"
    local variant="$2"
    local tag="$3"
    
    local image="ghcr.io/ublue-os/${family}"
    
    if [[ -n "$variant" ]]; then
        image="${image}-${variant}"
    fi
    
    if [[ -n "$tag" ]]; then
        image="${image}:${tag}"
    fi
    
    echo "$image"
}

get_available_targets() {
    local current_family="$1"
    local current_variant="$2"
    local current_tag="$3"
    
    local target_family
    target_family=$(get_target_family)
    
    local cache_file="$SCRIPT_DIR/../data/variants-cache.json"
    
    if [[ -f "$cache_file" ]]; then
        local cached_images
        cached_images=$(jq -r ".$target_family.images[]" "$cache_file" 2>/dev/null)
        
        if [[ -n "$cached_images" ]]; then
            local targets=()
            
            while IFS= read -r img; do
                [[ -z "$img" ]] && continue
                
                if [[ -n "$current_variant" ]]; then
                    if [[ "$img" == *"-$current_variant:"* || "$img" == *"$target_family:$current_tag" ]]; then
                        targets+=("$img")
                    fi
                else
                    if [[ "$img" == *":$current_tag" ]]; then
                        targets+=("$img")
                    fi
                fi
            done <<< "$cached_images"
            
            if [[ ${#targets[@]} -gt 0 ]]; then
                printf '%s\n' "${targets[@]}" | sort -u
                return 0
            fi
            
            echo "$cached_images" | head -10
            return 0
        fi
    fi
    
    local targets=()
    
    local variant_suffix=""
    if [[ -n "$current_variant" ]]; then
        variant_suffix="-$current_variant"
    fi
    
    targets+=("${target_family}${variant_suffix}:${current_tag}")
    
    if [[ "$current_tag" != "stable" ]]; then
        targets+=("${target_family}${variant_suffix}:stable")
    fi
    
    if [[ "$current_tag" != "latest" ]]; then
        targets+=("${target_family}${variant_suffix}:latest")
    fi
    
    printf '%s\n' "${targets[@]}" | sort -u
}

display_image_menu() {
    local targets
    mapfile -t targets < <(get_available_targets "$SOURCE_FAMILY" "$SOURCE_VARIANT" "$SOURCE_TAG")
    
    print_header "MIGRATION TARGET SELECTION"
    
    echo -e "Current: ${BOLD}${SOURCE_IMAGE}${RESET}"
    echo ""
    echo "Available targets:"
    echo ""
    
    local i=1
    local recommended=""
    
    for target in "${targets[@]}"; do
        if [[ "$target" == *"${SOURCE_VARIANT:-standard}"* && "$target" == *":${SOURCE_TAG}" ]]; then
            recommended=" (Recommended - matches your variant)"
        else
            recommended=""
        fi
        
        echo -e "  ${BOLD}$i${RESET}. ${target}${recommended}"
        ((i++))
    done
    
    echo ""
    read -rp "Select target [1-$((i-1))]: " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#targets[@]} ]]; then
        TARGET_IMAGE="${targets[$((selection-1))]}"
    else
        error "Invalid selection: $selection"
    fi
    
    parse_target_image
}

parse_target_image() {
    local image_name
    image_name=$(basename "$TARGET_IMAGE")
    
    if [[ "$TARGET_IMAGE" == *"bluefin"* ]]; then
        TARGET_FAMILY="bluefin"
        TARGET_DE="gnome"
    elif [[ "$TARGET_IMAGE" == *"aurora"* ]]; then
        TARGET_FAMILY="aurora"
        TARGET_DE="kde"
    else
        error "Unknown target image family: $TARGET_IMAGE"
    fi
    
    if [[ "$TARGET_IMAGE" == *"-dx"* ]]; then
        TARGET_VARIANT="dx"
    elif [[ "$TARGET_IMAGE" == *"-nvidia-open"* ]]; then
        TARGET_VARIANT="nvidia-open"
    elif [[ "$TARGET_IMAGE" == *"-nvidia"* ]]; then
        TARGET_VARIANT="nvidia"
    elif [[ "$TARGET_IMAGE" == *"-asus"* ]]; then
        TARGET_VARIANT="asus"
    else
        TARGET_VARIANT=""
    fi
    
    if [[ "$TARGET_IMAGE" == *":"* ]]; then
        TARGET_TAG="${TARGET_IMAGE##*:}"
    else
        TARGET_TAG="stable"
    fi
    
    debug "Target: $TARGET_FAMILY ($TARGET_DE), variant=$TARGET_VARIANT, tag=$TARGET_TAG"
}

is_bluefin() {
    [[ "$SOURCE_FAMILY" == "bluefin" ]]
}

is_aurora() {
    [[ "$SOURCE_FAMILY" == "aurora" ]]
}

is_gnome() {
    [[ "$SOURCE_DE" == "gnome" ]]
}

is_kde() {
    [[ "$SOURCE_DE" == "kde" ]]
}

migrating_to_gnome() {
    [[ "$TARGET_DE" == "gnome" ]]
}

migrating_to_kde() {
    [[ "$TARGET_DE" == "kde" ]]
}

get_display_manager() {
    case "$1" in
        gnome) echo "gdm" ;;
        kde)   echo "sddm" ;;
        *)     echo "" ;;
    esac
}

print_migration_summary() {
    print_header "MIGRATION SUMMARY"
    
    echo -e "  ${BOLD}Source:${RESET}      $SOURCE_FAMILY ($SOURCE_DE)"
    echo -e "  ${BOLD}Source Image:${RESET} $SOURCE_IMAGE"
    echo ""
    echo -e "  ${BOLD}Target:${RESET}      $TARGET_FAMILY ($TARGET_DE)"
    echo -e "  ${BOLD}Target Image:${RESET} $TARGET_IMAGE"
    echo ""
    
    if migrating_to_kde; then
        echo -e "${YELLOW}⚠ WARNING: Switching to KDE will reset GNOME-specific settings.${RESET}"
        echo -e "  Your Flatpaks, Homebrew, and user data will be preserved."
    elif migrating_to_gnome; then
        echo -e "${YELLOW}⚠ WARNING: Switching to GNOME will reset KDE-specific settings.${RESET}"
        echo -e "  Your Flatpaks, Homebrew, and user data will be preserved."
    fi
}
