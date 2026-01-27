{
  description = "Nix package for Claude Code - AI coding assistant in your terminal";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      overlay = final: prev: {
        claude-code = final.callPackage ./package.nix { runtime = "native"; };
        claude-code-node = final.callPackage ./package.nix { runtime = "node"; };
        claude-code-bun = final.callPackage ./package.nix { runtime = "bun"; };
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
          claude-code-node = pkgs.claude-code-node;
          claude-code-bun = pkgs.claude-code-bun;
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
          claude-code-node = {
            type = "app";
            program = "${pkgs.claude-code-node}/bin/claude-node";
          };
          claude-code-bun = {
            type = "app";
            program = "${pkgs.claude-code-bun}/bin/claude-bun";
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
