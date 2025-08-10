#!/usr/bin/env bash
set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

readonly NPM_REGISTRY_URL="https://registry.npmjs.org"
readonly PACKAGE_NAME="@anthropic-ai/claude-code"
readonly BUILD_LOG_FILE="/tmp/claude-code-build.log"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

get_current_version() {
    sed -n 's/.*claudeCodeVersion = "\([^"]*\)".*/\1/p' flake.nix | head -1 || echo "unknown"
}

get_latest_version_from_npm() {
    if command -v curl >/dev/null 2>&1; then
        curl -s "$NPM_REGISTRY_URL/$PACKAGE_NAME/latest" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p'
    else
        npm view "$PACKAGE_NAME" version 2>/dev/null || {
            log_error "Failed to fetch latest version from npm"
            exit 1
        }
    fi
}

fetch_source_hash() {
    local version="$1"
    local tarball_url="$NPM_REGISTRY_URL/$PACKAGE_NAME/-/claude-code-$version.tgz"
    
    local sha256_hash=$(nix-prefetch-url --type sha256 --unpack "$tarball_url" 2>/dev/null | tail -1)
    nix hash to-sri --type sha256 "$sha256_hash"
}

extract_npm_deps_hash_from_build_error() {
    grep "got:" "$BUILD_LOG_FILE" | head -1 | awk '{print $2}'
}

update_flake_version() {
    local version="$1"
    sed -i.bak "s/claudeCodeVersion = \".*\"/claudeCodeVersion = \"$version\"/" flake.nix
}

update_flake_source_hash() {
    local hash="$1"
    sed -i.bak "s|claudeCodeSrcHash = \".*\"|claudeCodeSrcHash = \"$hash\"|" flake.nix
}

update_flake_npm_deps_hash() {
    local hash="$1"
    sed -i.bak "s|claudeCodeNpmDepsHash = \".*\"|claudeCodeNpmDepsHash = \"$hash\"|" flake.nix
}

restore_flake_backup() {
    mv flake.nix.bak flake.nix
}

cleanup_flake_backup() {
    rm -f flake.nix.bak
}

build_package() {
    nix build .#claude-code 2>&1 | tee "$BUILD_LOG_FILE"
}

update_to_version() {
    local new_version="$1"
    
    log_info "Updating to version $new_version..."
    
    update_flake_version "$new_version"
    
    log_info "Fetching source tarball hash..."
    local source_hash=$(fetch_source_hash "$new_version")
    update_flake_source_hash "$source_hash"
    
    log_info "Calculating npm dependencies hash..."
    if ! build_package; then
        local npm_deps_hash=$(extract_npm_deps_hash_from_build_error)
        
        if [ -n "$npm_deps_hash" ]; then
            log_info "Found npm deps hash: $npm_deps_hash"
            update_flake_npm_deps_hash "$npm_deps_hash"
        else
            log_error "Could not extract npm deps hash from build output"
            restore_flake_backup
            exit 1
        fi
    else
        log_info "Build succeeded without needing npm deps hash update"
    fi
    
    cleanup_flake_backup
    
    log_info "Verifying build..."
    if build_package > /dev/null 2>&1; then
        log_info "✅ Build successful!"
        return 0
    else
        log_error "Build verification failed"
        return 1
    fi
}

ensure_in_repository_root() {
    if [ ! -f "flake.nix" ]; then
        log_error "flake.nix not found. Please run this script from the repository root."
        exit 1
    fi
}

ensure_required_tools_installed() {
    command -v nix >/dev/null 2>&1 || { log_error "nix is required but not installed."; exit 1; }
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
    echo "  $0 --version 1.0.73   # Update to specific version"
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
    git diff --stat flake.nix flake.lock
}

main() {
    ensure_in_repository_root
    ensure_required_tools_installed
    
    local args=$(parse_arguments "$@")
    local target_version=$(echo "$args" | cut -d'|' -f1)
    local check_only=$(echo "$args" | cut -d'|' -f2)
    
    local current_version=$(get_current_version)
    local latest_version=$(get_latest_version_from_npm)
    
    if [ -n "$target_version" ]; then
        latest_version="$target_version"
    fi
    
    log_info "Current version: $current_version"
    log_info "Latest version: $latest_version"
    
    if [ "$current_version" = "$latest_version" ]; then
        log_info "Already up to date!"
        exit 0
    fi
    
    if [ "$check_only" = true ]; then
        log_info "Update available: $current_version → $latest_version"
        exit 0
    fi
    
    update_to_version "$latest_version"
    
    log_info "Successfully updated claude-code from $current_version to $latest_version"
    
    update_flake_lock
    show_changes
}

main "$@"