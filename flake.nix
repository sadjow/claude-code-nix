{
  description = "Nix package for Claude Code - AI coding assistant in your terminal";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      claudeCodeVersion = "1.0.72";
      claudeCodeSrcHash = "sha256-1vIElqZ5sk62o1amdfOqhmSG4B5wzKWDLcCgvQO4a5o=";
      claudeCodeNpmDepsHash = "sha256-LkQf2lW6TM1zRr10H7JgtnE+dy0CE7WCxF4GhTd4GT4=";
      
      overlay = final: prev: {
        claude-code = prev.claude-code.overrideAttrs (oldAttrs: rec {
          version = claudeCodeVersion;
          
          src = final.fetchzip {
            url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
            hash = claudeCodeSrcHash;
          };
          
          npmDepsHash = claudeCodeNpmDepsHash;
          
          postInstall = ''
            wrapProgram $out/bin/claude \
              --set DISABLE_AUTOUPDATER 1 \
              --set CLAUDE_EXECUTABLE_PATH "\$HOME/.local/bin/claude" \
              --unset DEV
          '';
        });
      };
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ overlay ];
        };
      in
      {
        packages = {
          default = pkgs.claude-code;
          claude-code = pkgs.claude-code;
        };
        
        apps = {
          default = {
            type = "app";
            program = "${pkgs.claude-code}/bin/claude";
          };
          claude-code = {
            type = "app";
            program = "${pkgs.claude-code}/bin/claude";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixpkgs-fmt
            nix-prefetch-git
            cachix
          ];
        };
      }) // {
        overlays.default = overlay;
      };
}