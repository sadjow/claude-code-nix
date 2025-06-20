# Claude Code Package
# 
# This package installs Claude Code with its own Node.js runtime to ensure
# it's always available regardless of project-specific Node.js versions.
#
# Problem: When using devenv, asdf, or other Node.js version managers,
# Claude Code installed via npm might not be available or compatible.
#
# Solution: Install Claude Code through Nix with a bundled Node.js v20 runtime.

{ lib
, stdenv
, nodejs_20
, cacert
, bash
}:

stdenv.mkDerivation rec {
  pname = "claude-code";
  version = "1.0.30";  # Update this to install a newer version

  # Don't try to unpack a source tarball - we'll download via npm
  dontUnpack = true;

  # Build dependencies
  nativeBuildInputs = [ 
    nodejs_20   # Use Node.js v20 for compatibility
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
    ${nodejs_20}/bin/npm config set cafile $SSL_CERT_FILE
    
    # Install claude-code from npm registry
    # --prefix=$out installs it to our output directory
    ${nodejs_20}/bin/npm install -g --prefix=$out @anthropic-ai/claude-code@${version}
  '';

  installPhase = ''
    # The npm-generated binary has issues with env and paths
    # Remove it so we can create our own wrapper
    rm -f $out/bin/claude
    
    # Create a wrapper script that:
    # 1. Uses NODE_PATH to find modules without changing directory
    # 2. Runs claude from the user's current directory
    # 3. Passes all arguments through
    mkdir -p $out/bin
    cat > $out/bin/claude << 'EOF'
    #!${bash}/bin/bash
    # Set NODE_PATH to find the claude-code modules
    export NODE_PATH="$out/lib/node_modules"
    # Run claude from current directory
    exec ${nodejs_20}/bin/node --no-warnings --enable-source-maps "$out/lib/node_modules/@anthropic-ai/claude-code/cli.js" "$@"
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