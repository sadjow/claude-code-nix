{ lib
, stdenv
, fetchurl
, makeBinaryWrapper
, autoPatchelfHook
, procps
, ripgrep
, bubblewrap
, socat
, binName ? "claude"
}:

let
  version = "2.1.314";

  platformMap = {
    "aarch64-darwin" = "darwin-arm64";
    "x86_64-darwin" = "darwin-x64";
    "x86_64-linux" = "linux-x64";
    "aarch64-linux" = "linux-arm64";
  };

  platform = platformMap.${stdenv.hostPlatform.system} or
    (throw "Claude Code is not supported on ${stdenv.hostPlatform.system}. Supported: aarch64-darwin, x86_64-darwin, x86_64-linux, aarch64-linux");

  nativeHashes = {
    "darwin-arm64" = "1v9jm1xri0ik85a56fp1hkh2bakj7c5pc4yznzy4qyzhlswygmi1";
    "darwin-x64" = "1y3lq64x262m0rscn4hx4v7r96p71k7vrj15ignfqn5312ipjis0";
    "linux-x64" = "1525z32inr38p1zzak46b2pgzcg0macaws4gava8hpag9hmh91s4";
    "linux-arm64" = "1wiy1zpk1px8xardgq72pkpvmg1b362pjy9xjlws91qcbn7hlv56";
  };

  # Primary host is the Anthropic-branded CDN so users can verify the source;
  # the GCS bucket is the direct origin and stays as a fallback if the CDN is
  # unavailable. The sha256 pin guarantees both resolve to identical bytes.
  nativeBinary = fetchurl {
    urls = [
      "https://downloads.claude.ai/claude-code-releases/${version}/${platform}/claude"
      "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/${platform}/claude"
    ];
    sha256 = nativeHashes.${platform};
  };
in
stdenv.mkDerivation {
  pname = "claude-code";
  inherit version;

  dontUnpack = true;
  # Stripping corrupts the embedded Bun trailer.
  dontStrip = true;

  nativeBuildInputs = [ makeBinaryWrapper ]
    ++ lib.optionals stdenv.hostPlatform.isElf [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin

    install -m755 ${nativeBinary} $out/bin/.claude-unwrapped

    makeBinaryWrapper $out/bin/.claude-unwrapped $out/bin/${binName} \
      --inherit-argv0 \
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
  '';

  meta = with lib; {
    description = "Claude Code - AI coding assistant in your terminal";
    homepage = "https://www.anthropic.com/claude-code";
    license = licenses.unfree;
    platforms = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
    mainProgram = binName;
  };
}
