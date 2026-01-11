# Claude Code Package
#
# This package installs Claude Code with its own JavaScript runtime to ensure
# it's always available regardless of project-specific Node.js versions.
#
# Problem: When using devenv, asdf, or other Node.js version managers,
# Claude Code installed via npm might not be available or compatible.
#
# Solution: Install Claude Code through Nix with a bundled runtime (Node.js or Bun).

{ lib
, stdenv
, fetchurl
, nodejs_22
, bun
, cacert
, bash
, runtime ? "node"  # "node" or "bun"
}:

let
  version = "2.1.4";  # Update this to install a newer version

  # Pre-fetch the npm package as a Fixed Output Derivation
  # This allows network access during fetch phase for sandbox compatibility
  claudeCodeTarball = fetchurl {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
    # To get new hash when updating version:
    # nix-prefetch-url https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-VERSION.tgz
    sha256 = "0wfpig6s5zwxzf2rhsh2n9jvn6b969d8zw3p9qpzz36mmgsc64c1";
  };

  # Runtime-specific configuration
  runtimeConfig = {
    node = {
      pkg = nodejs_22;
      runtimeBin = "${nodejs_22}/bin/node";
      npmBin = "${nodejs_22}/bin/npm";
      runCmd = "${nodejs_22}/bin/node --no-warnings --enable-source-maps";
      nativeBuildInputs = [ nodejs_22 cacert ];
      description = "Claude Code (Node.js) - AI coding assistant in your terminal";
      binName = "claude";
    };
    bun = {
      pkg = bun;
      runtimeBin = "${bun}/bin/bun";
      npmBin = "${bun}/bin/bun";
      runCmd = "${bun}/bin/bun run";
      nativeBuildInputs = [ bun cacert ];
      description = "Claude Code (Bun) - AI coding assistant in your terminal";
      binName = "claude-bun";
    };
  };

  selected = runtimeConfig.${runtime};
in
stdenv.mkDerivation rec {
  pname = if runtime == "node" then "claude-code" else "claude-code-${runtime}";
  inherit version;

  # Don't try to unpack a source tarball - we'll handle it in buildPhase
  dontUnpack = true;

  # Build dependencies
  nativeBuildInputs = selected.nativeBuildInputs;

  buildPhase = ''
    # Create a temporary HOME for package manager to use during build
    export HOME=$TMPDIR
    mkdir -p $HOME/.npm $HOME/.bun

    # Configure SSL certificates
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    export NODE_EXTRA_CA_CERTS=$SSL_CERT_FILE

    ${if runtime == "node" then ''
    # Node.js: Configure npm
    ${selected.npmBin} config set cafile $SSL_CERT_FILE
    ${selected.npmBin} config set offline true

    # Install claude-code from the pre-fetched tarball
    ${selected.npmBin} install -g --prefix=$out ${claudeCodeTarball}
    '' else ''
    # Bun: Extract tarball and install
    mkdir -p $out/lib/node_modules/@anthropic-ai
    tar -xzf ${claudeCodeTarball} -C $out/lib/node_modules/@anthropic-ai
    mv $out/lib/node_modules/@anthropic-ai/package $out/lib/node_modules/@anthropic-ai/claude-code

    # Install dependencies using bun (skip scripts to avoid authorization check)
    cd $out/lib/node_modules/@anthropic-ai/claude-code
    ${selected.npmBin} install --production --ignore-scripts
    ''}
  '';

  installPhase = ''
    # Remove any npm-generated binary (has issues with env and paths)
    rm -f $out/bin/claude

    # Create a wrapper script that:
    # 1. Uses NODE_PATH to find modules without changing directory
    # 2. Runs claude from the user's current directory
    # 3. Passes all arguments through
    # 4. Preserves the consistent path for settings
    mkdir -p $out/bin
    cat > $out/bin/${selected.binName} << 'EOF'
#!${bash}/bin/bash
# Set NODE_PATH to find the claude-code modules
export NODE_PATH="$out/lib/node_modules"

# Set a consistent executable path for claude to prevent permission resets
# This makes macOS and claude think it's always the same binary
export CLAUDE_EXECUTABLE_PATH="$HOME/.local/bin/${selected.binName}"

# Disable automatic update checks since updates should go through Nix
export DISABLE_AUTOUPDATER=1

# Create a temporary npm wrapper that Claude Code will use internally
# This ensures it doesn't interfere with project npm versions
export _CLAUDE_NPM_WRAPPER="$(mktemp -d)/npm"
cat > "$_CLAUDE_NPM_WRAPPER" << 'NPM_EOF'
#!${bash}/bin/bash
# Intercept npm commands that might trigger update checks
if [[ "$1" = "update" ]] || [[ "$1" = "outdated" ]] || [[ "$1" =~ ^view ]] && [[ "$2" =~ @anthropic-ai/claude-code ]]; then
    echo "Updates are managed through Nix. Current version: ${version}"
    exit 0
fi
# Pass through to bundled package manager for other commands
exec ${selected.npmBin} "$@"
NPM_EOF
chmod +x "$_CLAUDE_NPM_WRAPPER"

# Only add our npm wrapper to PATH for Claude Code's internal use
export PATH="$(dirname "$_CLAUDE_NPM_WRAPPER"):$PATH"

# Run claude from current directory
exec ${selected.runCmd} "$out/lib/node_modules/@anthropic-ai/claude-code/cli.js" "$@"
EOF
    chmod +x $out/bin/${selected.binName}

    # Replace $out placeholder with the actual output path
    substituteInPlace $out/bin/${selected.binName} \
      --replace '$out' "$out"
  '';

  meta = with lib; {
    description = selected.description;
    homepage = "https://www.anthropic.com/claude-code";
    license = licenses.unfree; # Claude Code is proprietary
    platforms = if runtime == "bun"
      then [ "aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux" ]
      else platforms.all;
  };
}
