#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get current version from flake.nix
get_current_version() {
    # Use sed for portability (grep -P not available on macOS)
    sed -n 's/.*claudeCodeVersion = "\([^"]*\)".*/\1/p' flake.nix | head -1 || echo "unknown"
}

# Get latest version from npm
get_latest_version() {
    # Use curl to fetch directly from npm registry
    if command -v curl >/dev/null 2>&1; then
        curl -s https://registry.npmjs.org/@anthropic-ai/claude-code/latest | sed -n 's/.*"version":"\([^"]*\)".*/\1/p'
    else
        # Fallback to npm
        npm view @anthropic-ai/claude-code version 2>/dev/null || {
            log_error "Failed to fetch latest version from npm"
            exit 1
        }
    fi
}

# Update version and hashes in flake.nix
update_flake() {
    local new_version="$1"
    
    log_info "Updating to version $new_version..."
    
    # Update version
    sed -i.bak "s/claudeCodeVersion = \".*\"/claudeCodeVersion = \"$new_version\"/" flake.nix
    
    # Get the new source hash
    log_info "Fetching source tarball hash..."
    local src_url="https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-$new_version.tgz"
    local src_hash=$(nix-prefetch-url --type sha256 --unpack "$src_url" 2>/dev/null | tail -1)
    local src_hash_sri=$(nix hash to-sri --type sha256 "$src_hash")
    
    # Update source hash
    sed -i.bak "s|claudeCodeSrcHash = \".*\"|claudeCodeSrcHash = \"$src_hash_sri\"|" flake.nix
    
    # Build to get npm deps hash
    log_info "Calculating npm dependencies hash..."
    local npm_deps_hash=""
    
    if ! nix build .#claude-code 2>&1 | tee /tmp/build.log; then
        # Extract the correct npm deps hash from the error message
        npm_deps_hash=$(grep "got:" /tmp/build.log | head -1 | awk '{print $2}')
        
        if [ -n "$npm_deps_hash" ]; then
            log_info "Found npm deps hash: $npm_deps_hash"
            sed -i.bak "s|claudeCodeNpmDepsHash = \".*\"|claudeCodeNpmDepsHash = \"$npm_deps_hash\"|" flake.nix
        else
            log_error "Could not extract npm deps hash from build output"
            # Restore backup
            mv flake.nix.bak flake.nix
            exit 1
        fi
    else
        log_info "Build succeeded without needing npm deps hash update"
    fi
    
    # Clean up backup
    rm -f flake.nix.bak
    
    # Try building again to verify
    log_info "Verifying build..."
    if nix build .#claude-code; then
        log_info "✅ Build successful!"
        return 0
    else
        log_error "Build verification failed"
        return 1
    fi
}

# Main function
main() {
    # Check if we're in the right directory
    if [ ! -f "flake.nix" ]; then
        log_error "flake.nix not found. Please run this script from the repository root."
        exit 1
    fi
    
    # Check for required tools
    command -v nix >/dev/null 2>&1 || { log_error "nix is required but not installed."; exit 1; }
    command -v npm >/dev/null 2>&1 || { log_error "npm is required but not installed."; exit 1; }
    
    # Parse arguments
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
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Get versions
    local current_version=$(get_current_version)
    local latest_version=$(get_latest_version)
    
    if [ -n "$target_version" ]; then
        latest_version="$target_version"
    fi
    
    log_info "Current version: $current_version"
    log_info "Latest version: $latest_version"
    
    # Check if update is needed
    if [ "$current_version" = "$latest_version" ]; then
        log_info "Already up to date!"
        exit 0
    fi
    
    if [ "$check_only" = true ]; then
        log_info "Update available: $current_version → $latest_version"
        exit 0
    fi
    
    # Perform update
    update_flake "$latest_version"
    
    log_info "Successfully updated claude-code from $current_version to $latest_version"
    
    # Update flake.lock
    if command -v nix >/dev/null 2>&1; then
        log_info "Updating flake.lock..."
        nix flake update
    fi
    
    # Show what changed
    echo ""
    log_info "Changes made:"
    git diff --stat flake.nix flake.lock
}

# Run main function
main "$@"