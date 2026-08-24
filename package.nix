# Claude Code Package
#
# This package installs Claude Code with your choice of runtime:
# - native: Pre-built binary from Anthropic (default, recommended)
# - node: Launch the native binary via Node.js (upstream cli-wrapper)
# - bun:  Launch the native binary via Bun (upstream cli-wrapper)
#
# The native runtime is self-contained and doesn't require Node.js or Bun.

{ lib
, stdenv
, fetchurl
, nodejs_22
, bun
, cacert
, bash
, makeBinaryWrapper
, autoPatchelfHook
, procps
, ripgrep
, bubblewrap
, socat
, runtime ? "native"  # "native", "node", or "bun"
, nativeBinName ? "claude"
, nodeBinName ? "claude-node"
, bunBinName ? "claude-bun"
}:

let
  version = "2.1.241";

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
    "darwin-arm64" = "03c2cig7kw8wbjzc4aw0ijis88ld95nqplqwbwglbd6k89yfp58l";
    "darwin-x64" = "03f12q9qzsw0590zhgcclfa13xlsysb4vwbnnksmwj36rv5bh0fg";
    "linux-x64" = "1f1pf2yb7k0xr3w49wbqa223c6lyabv9j17wh5jvg0pzdj3bsw87";
    "linux-arm64" = "1zm2jklav8xz9bkdm4v2b2i1z066bfj6sra6xs5fzn5y7s4wpc1d";
  };

  # Native binary URL
  nativeBinaryUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/${platform}/claude";

  # Fetch native binary. Needed by every runtime now: the native runtime runs
  # it directly; node/bun launch it via upstream's cli-wrapper.cjs (upstream no
  # longer ships a JS CLI, only a launcher around this platform binary).
  nativeBinary = if platform != null then
    fetchurl {
      url = nativeBinaryUrl;
      sha256 = nativeHashes.${platform};
    }
  else null;

  # Upstream delivers the CLI as a platform-specific native binary via
  # optionalDependencies; cli-wrapper.cjs resolves it by this package name.
  optDepMap = {
    "aarch64-darwin" = "claude-code-darwin-arm64";
    "x86_64-darwin" = "claude-code-darwin-x64";
    "x86_64-linux" = "claude-code-linux-x64";
    "aarch64-linux" = "claude-code-linux-arm64";
  };
  optDepName = optDepMap.${stdenv.hostPlatform.system} or null;

  # Pre-fetch the npm package for node/bun runtimes
  claudeCodeTarball = if runtime != "native" then
    fetchurl {
      url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
      sha256 = "1rp7l90zazyrff2i94vvma516jnpvsvm9bp1dhsiqhv5kbzm48km";
    }
  else null;

  # Runtime-specific configuration
  runtimeConfig = {
    native = {
      nativeBuildInputs = [ makeBinaryWrapper ]
        ++ lib.optionals stdenv.hostPlatform.isElf [ autoPatchelfHook ];
      buildInputs = [];
      description = "Claude Code (Native Binary) - AI coding assistant in your terminal";
      binName = nativeBinName;
    };
    node = {
      pkg = nodejs_22;
      runtimeBin = "${nodejs_22}/bin/node";
      npmBin = "${nodejs_22}/bin/npm";
      runCmd = "${nodejs_22}/bin/node --no-warnings --enable-source-maps";
      nativeBuildInputs = [ nodejs_22 ] ++ lib.optionals stdenv.hostPlatform.isElf [ autoPatchelfHook ];
      buildInputs = [];
      description = "Claude Code (Node.js) - AI coding assistant in your terminal";
      binName = nodeBinName;
    };
    bun = {
      pkg = bun;
      runtimeBin = "${bun}/bin/bun";
      npmBin = "${bun}/bin/bun";
      runCmd = "${bun}/bin/bun run";
      nativeBuildInputs = [ bun ] ++ lib.optionals stdenv.hostPlatform.isElf [ autoPatchelfHook ];
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

  # The native binary is a Bun-compiled single-file exe; stripping corrupts it.
  dontStrip = true;

  nativeBuildInputs = selected.nativeBuildInputs;
  buildInputs = selected.buildInputs;

  buildPhase =
    if runtime == "native" then ''
      runHook preBuild
      runHook postBuild
    '' else ''
      runHook preBuild

      # Extract upstream's launcher package (cli-wrapper.cjs, install.cjs, ...)
      mkdir -p $out/lib/node_modules/@anthropic-ai
      tar -xzf ${claudeCodeTarball} -C $out/lib/node_modules/@anthropic-ai
      mv $out/lib/node_modules/@anthropic-ai/package \
         $out/lib/node_modules/@anthropic-ai/claude-code

      # Supply the platform-native binary where cli-wrapper.cjs resolves it.
      # Reuse the same binary the native runtime fetches (no extra hashes).
      mkdir -p $out/lib/node_modules/@anthropic-ai/${optDepName}
      install -m755 ${nativeBinary} \
        $out/lib/node_modules/@anthropic-ai/${optDepName}/claude
      printf '{"name":"@anthropic-ai/%s","version":"%s"}\n' \
        '${optDepName}' '${version}' \
        > $out/lib/node_modules/@anthropic-ai/${optDepName}/package.json
    '' + lib.optionalString (runtime != "native" && stdenv.hostPlatform.isLinux) ''
      # Guard against Node's libc (musl) detection resolving a -musl variant.
      ln -s ${optDepName} \
        $out/lib/node_modules/@anthropic-ai/${optDepName}-musl
    '' + lib.optionalString (runtime != "native") ''
      runHook postBuild
    '';

  installPhase =
    if runtime == "native" then ''
      runHook preInstall
      mkdir -p $out/bin

      install -m755 ${nativeBinary} $out/bin/.claude-unwrapped

      makeBinaryWrapper $out/bin/.claude-unwrapped $out/bin/${selected.binName} \
        --set DISABLE_AUTOUPDATER 1 \
        --set DISABLE_INSTALLATION_CHECKS 1 \
        --set USE_BUILTIN_RIPGREP 0 \
        --prefix PATH : ${
          lib.makeBinPath (
            [
              procps
              ripgrep
            ]
            ++ lib.optionals stdenv.hostPlatform.isLinux [
              bubblewrap
              socat
            ]
          )
        }

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
exec ${selected.runCmd} "$out/lib/node_modules/@anthropic-ai/claude-code/cli-wrapper.cjs" "$@"
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
      [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
    mainProgram = selected.binName;
  };
}
