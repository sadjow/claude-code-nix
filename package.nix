# Claude Code Package
# 
# This package installs Claude Code with its own Node.js runtime to ensure
# it's always available regardless of project-specific Node.js versions.
#
# Problem: When using devenv, asdf, or other Node.js version managers,
# Claude Code installed via npm might not be available or compatible.
#
# Solution: Install Claude Code through Nix with a bundled Node.js v22 runtime.

{ lib
, stdenv
, nodejs_22
, cacert
, bash
}:

stdenv.mkDerivation rec {
  pname = "claude-code";
  version = "1.0.41";  # Update this to install a newer version

  # Don't try to unpack a source tarball - we'll download via npm
  dontUnpack = true;

  # Build dependencies
  nativeBuildInputs = [ 
    nodejs_22   # Use Node.js v22 LTS for compatibility
    cacert      # SSL certificates for npm
  ];
  
  buildPhase = ''
    # Create a temporary HOME for npm to use during build
    export HOME=$TMPDIR
    mkdir -p $HOME/.npm
    
    # Configure npm to use Nix's SSL certificates
    # This is necessary because npm needs to verify SSL certificates
    # when downloading packages from the registry
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    export NODE_EXTRA_CA_CERTS=$SSL_CERT_FILE
    
    # Tell npm where to find certificates
    ${nodejs_22}/bin/npm config set cafile $SSL_CERT_FILE
    
    # Configure npm to handle network issues better
    ${nodejs_22}/bin/npm config set fetch-retries 5
    ${nodejs_22}/bin/npm config set fetch-retry-mintimeout 20000
    ${nodejs_22}/bin/npm config set fetch-retry-maxtimeout 120000
    
    # Install claude-code from npm registry
    # --prefix=$out installs it to our output directory
    ${nodejs_22}/bin/npm install -g --prefix=$out @anthropic-ai/claude-code@${version}
  '';

  installPhase = ''
    # The npm-generated binary has issues with env and paths
    # Remove it so we can create our own wrapper
    rm -f $out/bin/claude
    
    # Create a wrapper script that:
    # 1. Uses NODE_PATH to find modules without changing directory
    # 2. Runs claude from the user's current directory
    # 3. Passes all arguments through
    # 4. Preserves the consistent path for settings
    mkdir -p $out/bin
    cat > $out/bin/claude << 'EOF'
    #!${bash}/bin/bash
    # Set NODE_PATH to find the claude-code modules
    export NODE_PATH="$out/lib/node_modules"
    
    # Set a consistent executable path for claude to prevent permission resets
    # This makes macOS and claude think it's always the same binary
    export CLAUDE_EXECUTABLE_PATH="$HOME/.local/bin/claude"
    
    # Disable automatic update checks since updates should go through Nix
    export DISABLE_AUTOUPDATER=1
    
    # Create a temporary npm wrapper that Claude Code will use internally
    # This ensures it doesn't interfere with project npm versions
    export _CLAUDE_NPM_WRAPPER="$(mktemp -d)/npm"
    cat > "$_CLAUDE_NPM_WRAPPER" << 'NPM_EOF'
    #!${bash}/bin/bash
    # Intercept npm commands that might trigger update checks
    if [[ "$1" = "update" ]] || [[ "$1" = "outdated" ]] || [[ "$1" = "view" && "$2" =~ @anthropic-ai/claude-code ]]; then
        echo "Updates are managed through Nix. Current version: ${version}"
        exit 0
    fi
    # Pass through to bundled npm for other commands
    exec ${nodejs_22}/bin/npm "$@"
    NPM_EOF
    chmod +x "$_CLAUDE_NPM_WRAPPER"
    
    # Only add our npm wrapper to PATH for Claude Code's internal use
    export PATH="$(dirname "$_CLAUDE_NPM_WRAPPER"):$PATH"
    
    # Run claude from current directory
    exec ${nodejs_22}/bin/node --no-warnings --enable-source-maps "$out/lib/node_modules/@anthropic-ai/claude-code/cli.js" "$@"
    EOF
    chmod +x $out/bin/claude
    
    # Replace $out placeholder with the actual output path
    substituteInPlace $out/bin/claude \
      --replace '$out' "$out"
  '';

  meta = with lib; {
    description = "Claude Code - AI coding assistant in your terminal";
    homepage = "https://www.anthropic.com/claude-code";
    license = licenses.unfree; # Claude Code is proprietary
    platforms = platforms.all;
  };
}