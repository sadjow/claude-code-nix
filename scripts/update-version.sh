#!/usr/bin/env bash
set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

readonly NPM_REGISTRY_URL="https://registry.npmjs.org"
readonly PACKAGE_NAME="@anthropic-ai/claude-code"
readonly NATIVE_BASE_URL="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

# Native binary platforms
readonly NATIVE_PLATFORMS=("darwin-arm64" "darwin-x64" "linux-x64" "linux-arm64")

readonly MAX_RETRIES=3
readonly RETRY_BASE_DELAY=2

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

retry() {
    local max_attempts="$1"
    local base_delay="$2"
    shift 2

    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        local result
        result=$("$@") && [ -n "$result" ] && { echo "$result"; return 0; }

        if ((attempt < max_attempts)); then
            local delay=$((base_delay ** attempt))
            log_warn "Attempt $attempt/$max_attempts failed, retrying in ${delay}s..."
            sleep "$delay"
        fi
    done

    return 1
}

get_current_version() {
    sed -n 's/.*version = "\([^"]*\)".*/\1/p' package.nix | head -1 || echo "unknown"
}

fetch_npm_version() {
    if command -v curl >/dev/null 2>&1; then
        curl -sf --max-time 10 "$NPM_REGISTRY_URL/$PACKAGE_NAME/latest" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p'
    else
        npm view "$PACKAGE_NAME" version 2>/dev/null
    fi
}

get_latest_version_from_npm() {
    retry "$MAX_RETRIES" "$RETRY_BASE_DELAY" fetch_npm_version
}

fetch_tarball_hash() {
    local version="$1"
    local tarball_url="$NPM_REGISTRY_URL/$PACKAGE_NAME/-/claude-code-$version.tgz"

    local hash=$(nix-prefetch-url "$tarball_url" 2>/dev/null | tail -1)
    echo "$hash" | tr -d '\n'
}

fetch_native_hash() {
    local version="$1"
    local platform="$2"
    local binary_url="$NATIVE_BASE_URL/$version/$platform/claude"

    local hash=$(nix-prefetch-url "$binary_url" 2>/dev/null | tail -1)
    echo "$hash" | tr -d '\n'
}

update_package_version() {
    local version="$1"
    sed -i.bak "s/version = \".*\"/version = \"$version\"/" package.nix
}

update_npm_hash() {
    local hash="$1"
    # Update the npm tarball hash (the one after claudeCodeTarball fetchurl)
    # claudeCodeTarball and fetchurl are on different lines, so we need
    # to track state across multiple lines
    local temp_file=$(mktemp)
    awk -v hash="$hash" '
        /claudeCodeTarball = / { in_tarball_block=1 }
        in_tarball_block && /fetchurl/ { in_fetchurl_block=1 }
        in_fetchurl_block && /sha256 = / {
            sub(/sha256 = "[^"]*"/, "sha256 = \"" hash "\"")
            in_tarball_block=0
            in_fetchurl_block=0
        }
        in_tarball_block && /^[[:space:]]*else/ { in_tarball_block=0 }
        { print }
    ' package.nix > "$temp_file"
    mv "$temp_file" package.nix
}

update_native_hash() {
    local platform="$1"
    local hash="$2"
    local temp_file=$(mktemp)

    # Update the specific platform hash in nativeHashes
    awk -v platform="$platform" -v hash="$hash" '
        /nativeHashes = \{/ { in_native_block=1 }
        in_native_block && $0 ~ "\"" platform "\"" {
            sub(/= "[^"]*"/, "= \"" hash "\"")
        }
        in_native_block && /\};/ { in_native_block=0 }
        { print }
    ' package.nix > "$temp_file"
    mv "$temp_file" package.nix
}

cleanup_backup_files() {
    rm -f package.nix.bak
}

update_to_version() {
    local new_version="$1"

    log_info "Updating to version $new_version..."

    # Update version in package.nix
    update_package_version "$new_version"

    # Fetch and update npm tarball hash
    log_info "Fetching npm tarball hash..."
    local tarball_hash=$(fetch_tarball_hash "$new_version")
    if [ -z "$tarball_hash" ]; then
        log_error "Failed to fetch npm tarball hash"
        mv package.nix.bak package.nix
        exit 1
    fi
    log_info "NPM tarball hash: $tarball_hash"
    update_npm_hash "$tarball_hash"

    # Fetch and update native binary hashes
    log_info "Fetching native binary hashes..."
    for platform in "${NATIVE_PLATFORMS[@]}"; do
        log_info "  Fetching hash for $platform..."
        local native_hash=$(fetch_native_hash "$new_version" "$platform")
        if [ -z "$native_hash" ]; then
            log_error "Failed to fetch native hash for $platform"
            mv package.nix.bak package.nix
            exit 1
        fi
        log_info "  $platform: $native_hash"
        update_native_hash "$platform" "$native_hash"
    done

    cleanup_backup_files

    log_info "Verifying builds..."

    # Test native build (default)
    log_info "  Building claude-code (native)..."
    if ! nix build .#claude-code > /dev/null 2>&1; then
        log_error "Native build verification failed"
        return 1
    fi

    # Test node build
    log_info "  Building claude-code-node..."
    if ! nix build .#claude-code-node > /dev/null 2>&1; then
        log_error "Node build verification failed"
        return 1
    fi

    log_info "✅ All builds successful!"
    return 0
}

ensure_in_repository_root() {
    if [ ! -f "flake.nix" ] || [ ! -f "package.nix" ]; then
        log_error "flake.nix or package.nix not found. Please run this script from the repository root."
        exit 1
    fi
}

ensure_required_tools_installed() {
    command -v nix >/dev/null 2>&1 || { log_error "nix is required but not installed."; exit 1; }
    command -v nix-prefetch-url >/dev/null 2>&1 || { log_error "nix-prefetch-url is required but not installed."; exit 1; }
}

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --version VERSION  Update to specific version"
    echo "  --check           Only check for updates, don't apply"
    echo "  --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Update to latest version"
    echo "  $0 --check            # Check if update is available"
    echo "  $0 --version 1.0.82   # Update to specific version"
}

parse_arguments() {
    local target_version=""
    local check_only=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                target_version="$2"
                shift 2
                ;;
            --check)
                check_only=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    echo "$target_version|$check_only"
}

update_flake_lock() {
    if command -v nix >/dev/null 2>&1; then
        log_info "Updating flake.lock..."
        nix flake update
    fi
}

show_changes() {
    echo ""
    log_info "Changes made:"
    git diff --stat package.nix flake.lock 2>/dev/null || true
}

main() {
    ensure_in_repository_root
    ensure_required_tools_installed

    local args=$(parse_arguments "$@")
    local target_version=$(echo "$args" | cut -d'|' -f1)
    local check_only=$(echo "$args" | cut -d'|' -f2)

    local current_version=$(get_current_version)
    local latest_version

    if [ -n "$target_version" ]; then
        latest_version="$target_version"
    else
        latest_version=$(get_latest_version_from_npm) || true
        if [ -z "$latest_version" ]; then
            log_error "Failed to fetch latest version from npm after $MAX_RETRIES attempts"
            exit 1
        fi
    fi

    log_info "Current version: $current_version"
    log_info "Latest version: $latest_version"

    if [ "$current_version" = "$latest_version" ]; then
        log_info "Already up to date!"
        exit 0
    fi

    if [ "$check_only" = true ]; then
        log_info "Update available: $current_version → $latest_version"
        exit 1  # Exit with non-zero to indicate update is available
    fi

    update_to_version "$latest_version"

    log_info "Successfully updated claude-code from $current_version to $latest_version"

    update_flake_lock
    show_changes
}

main "$@"
