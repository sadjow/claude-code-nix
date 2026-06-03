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
  version = "2.1.162";

  platformMap = {
    "aarch64-darwin" = "darwin-arm64";
    "x86_64-darwin" = "darwin-x64";
    "x86_64-linux" = "linux-x64";
    "aarch64-linux" = "linux-arm64";
  };

  platform = platformMap.${stdenv.hostPlatform.system} or
    (throw "Claude Code is not supported on ${stdenv.hostPlatform.system}. Supported: aarch64-darwin, x86_64-darwin, x86_64-linux, aarch64-linux");

  nativeHashes = {
    "darwin-arm64" = "1lhpb84g91gn183qjcm7b4hrmlpwp64iacv41y8aqhrjlv97sh1d";
    "darwin-x64" = "0h8x0p398ymk2lai88k2q2ir960wyrvhhz817fr80njfyadp9wjk";
    "linux-x64" = "1lb19r8yq133yf2swv9agg8xvwqzfwj3qxbf9akzd246vsq4jyll";
    "linux-arm64" = "0381yh5gij1ghkn2075w71bj95fzz6bygjv9him45hzbvw1sd8pc";
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
