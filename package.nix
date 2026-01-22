# Claude Code Package (Pre-built Binary)
#
# Installs Claude Code from pre-built binaries distributed on the official CDN.
# NPM distribution is deprecated in favor of native binary releases.

{ lib
, stdenv
, fetchurl
, cacert
, version ? "2.1.15"
}:

let
  # Platform-specific binary URLs and checksums
  # Get latest checksums from: https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/{VERSION}/manifest.json
  binaries = {
    x86_64-linux = {
      url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/claude-code-${version}-linux-x64.tar.gz";
      sha256 = "37f8e874b8d07f3b60a3b66c7a01034837d1e333eb41552d0932d784255e862d";
    };
    aarch64-linux = {
      url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/claude-code-${version}-linux-arm64.tar.gz";
      sha256 = "20a520256b78aff56d4273d618c97965913e041a850fe6ceab9b714f57e39554";
    };
  };

  platform = stdenv.hostPlatform.system;
  binary = binaries.${platform} or (throw "Unsupported platform: ${platform}");

in
stdenv.mkDerivation rec {
  pname = "claude-code";
  inherit version;

  src = fetchurl {
    url = binary.url;
    sha256 = binary.sha256;
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    install -m 755 claude-code $out/bin/claude
  '';

  meta = with lib; {
    description = "Claude Code - AI coding assistant in your terminal";
    homepage = "https://www.anthropic.com/claude-code";
    license = licenses.unfree; # Claude Code is proprietary
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "claude";
  };
}
