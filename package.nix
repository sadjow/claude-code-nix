# Claude Code Package
#
# This package installs Claude Code with your choice of runtime:
# - native: Pre-built binary from Anthropic (default, recommended)
# - node: Run via Node.js from npm package
# - bun: Run via Bun from npm package
#
# The native runtime is self-contained and doesn't require Node.js or Bun.

{ lib
, stdenv
, fetchurl
, nodejs_22
, bun
, cacert
, bash
, patchelf
, autoPatchelfHook
, runtime ? "native"  # "native", "node", or "bun"
, nativeBinName ? "claude"
, nodeBinName ? "claude-node"
, bunBinName ? "claude-bun"
}:

let
  version = "2.1.20";

  # Platform mapping for native binaries (Nix system -> Anthropic platform)
  platformMap = {
    "aarch64-darwin" = "darwin-arm64";
    "x86_64-darwin" = "darwin-x64";
    "x86_64-linux" = "linux-x64";
    "aarch64-linux" = "linux-arm64";
  };

  platform = platformMap.${stdenv.hostPlatform.system} or null;

  # Native binary hashes per platform
  nativeHashes = {
    "darwin-arm64" = "134c2ws9w3l729490dizzvn5d2hxszjqvwswfzjyhjl5xnb3aw65";
    "darwin-x64" = "0idhd79v7lj96jz0j33x8fhjh06wsaqaz1067fqxk2y8f0kjjf0d";
    "linux-x64" = "1k2gaz4smd83azy9zsmw1x0ynb2wz605rsjf5pdqd93qaf7nklzr";
    "linux-arm64" = "16bgw4xa5y9vdccsdy3cg5gfca3ky5s6dwrmq8hinl58lk3h327b";
  };

  # Native binary URL
  nativeBinaryUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/${platform}/claude";

  # Fetch native binary (only when runtime is native and platform is supported)
  nativeBinary = if runtime == "native" && platform != null then
    fetchurl {
      url = nativeBinaryUrl;
      sha256 = nativeHashes.${platform};
    }
  else null;

  # Pre-fetch the npm package for node/bun runtimes
  claudeCodeTarball = if runtime != "native" then
    fetchurl {
      url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
      sha256 = "0jghdvs05rrd90pvc93ak432idp35353996z68zzvj1d4jgp4g6y";
    }
  else null;

  # Runtime-specific configuration
  runtimeConfig = {
    native = {
      nativeBuildInputs = lib.optionals stdenv.isLinux [ patchelf autoPatchelfHook ];
      buildInputs = lib.optionals stdenv.isLinux [ stdenv.cc.cc.lib ];
      description = "Claude Code (Native Binary) - AI coding assistant in your terminal";
      binName = nativeBinName;
    };
    node = {
      pkg = nodejs_22;
      runtimeBin = "${nodejs_22}/bin/node";
      npmBin = "${nodejs_22}/bin/npm";
      runCmd = "${nodejs_22}/bin/node --no-warnings --enable-source-maps";
      nativeBuildInputs = [ nodejs_22 cacert ];
      buildInputs = [];
      description = "Claude Code (Node.js) - AI coding assistant in your terminal";
      binName = nodeBinName;
    };
    bun = {
      pkg = bun;
      runtimeBin = "${bun}/bin/bun";
      npmBin = "${bun}/bin/bun";
      runCmd = "${bun}/bin/bun run";
      nativeBuildInputs = [ bun cacert ];
      buildInputs = [];
      description = "Claude Code (Bun) - AI coding assistant in your terminal";
      binName = bunBinName;
    };
  };

  selected = runtimeConfig.${runtime};
in
assert runtime == "native" -> platform != null ||
  throw "Native runtime not supported on ${stdenv.hostPlatform.system}. Supported: aarch64-darwin, x86_64-darwin, x86_64-linux, aarch64-linux";

stdenv.mkDerivation rec {
  pname = if runtime == "native" then "claude-code"
          else if runtime == "node" then "claude-code-node"
          else "claude-code-${runtime}";
  inherit version;

  dontUnpack = true;

  nativeBuildInputs = selected.nativeBuildInputs;
  buildInputs = selected.buildInputs;

  buildPhase = if runtime == "native" then ''
    runHook preBuild
    mkdir -p build
    cp ${nativeBinary} build/claude-raw
    chmod +x build/claude-raw
    runHook postBuild
  '' else ''
    runHook preBuild
    export HOME=$TMPDIR
    mkdir -p $HOME/.npm $HOME/.bun

    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    export NODE_EXTRA_CA_CERTS=$SSL_CERT_FILE

    ${if runtime == "node" then ''
    ${selected.npmBin} config set cafile $SSL_CERT_FILE
    ${selected.npmBin} config set offline true
    ${selected.npmBin} install -g --prefix=$out ${claudeCodeTarball}
    '' else ''
    mkdir -p $out/lib/node_modules/@anthropic-ai
    tar -xzf ${claudeCodeTarball} -C $out/lib/node_modules/@anthropic-ai
    mv $out/lib/node_modules/@anthropic-ai/package $out/lib/node_modules/@anthropic-ai/claude-code
    cd $out/lib/node_modules/@anthropic-ai/claude-code
    ${selected.npmBin} install --production --ignore-scripts
    ''}
    runHook postBuild
  '';

  installPhase = if runtime == "native" then ''
    runHook preInstall
    mkdir -p $out/bin

    # Install the patched binary
    cp build/claude-raw $out/bin/claude-raw
    chmod +x $out/bin/claude-raw

    # Create wrapper script
    cat > $out/bin/${selected.binName} << 'WRAPPER_EOF'
#!${bash}/bin/bash
export CLAUDE_EXECUTABLE_PATH="$HOME/.local/bin/${selected.binName}"
export DISABLE_AUTOUPDATER=1
export DISABLE_INSTALLATION_CHECKS=1
exec "$out/bin/claude-raw" "$@"
WRAPPER_EOF
    chmod +x $out/bin/${selected.binName}

    substituteInPlace $out/bin/${selected.binName} \
      --replace-fail '$out' "$out"
    runHook postInstall
  '' else ''
    runHook preInstall
    rm -f $out/bin/claude

    mkdir -p $out/bin
    cat > $out/bin/${selected.binName} << 'WRAPPER_EOF'
#!${bash}/bin/bash
export NODE_PATH="$out/lib/node_modules"
export CLAUDE_EXECUTABLE_PATH="$HOME/.local/bin/${selected.binName}"
export DISABLE_AUTOUPDATER=1
export DISABLE_INSTALLATION_CHECKS=1

export _CLAUDE_NPM_WRAPPER="$(mktemp -d)/npm"
cat > "$_CLAUDE_NPM_WRAPPER" << 'NPM_EOF'
#!${bash}/bin/bash
if [[ "$1" = "update" ]] || [[ "$1" = "outdated" ]] || [[ "$1" =~ ^view ]] && [[ "$2" =~ @anthropic-ai/claude-code ]]; then
    echo "Updates are managed through Nix. Current version: ${version}"
    exit 0
fi
exec ${selected.npmBin} "$@"
NPM_EOF
chmod +x "$_CLAUDE_NPM_WRAPPER"

export PATH="$(dirname "$_CLAUDE_NPM_WRAPPER"):$PATH"
exec ${selected.runCmd} "$out/lib/node_modules/@anthropic-ai/claude-code/cli.js" "$@"
WRAPPER_EOF
    chmod +x $out/bin/${selected.binName}

    substituteInPlace $out/bin/${selected.binName} \
      --replace-fail '$out' "$out"
    runHook postInstall
  '';

  meta = with lib; {
    description = selected.description;
    homepage = "https://www.anthropic.com/claude-code";
    license = licenses.unfree;
    platforms = if runtime == "native" then
      [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ]
    else if runtime == "bun" then
      [ "aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux" ]
    else
      platforms.all;
    mainProgram = selected.binName;
  };
}
