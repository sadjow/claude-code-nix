{
  description = "Nix package for Claude Code - AI coding assistant in your terminal";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    { self
    , nixpkgs
    , systems
    }:
    let
      inherit (nixpkgs) lib;
      eachSystem = f: lib.foldl' lib.recursiveUpdate { } (map f (import systems));

      overlay = final: prev: {
        claude-code = final.callPackage ./package.nix { };
      };
    in
    eachSystem
      (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ overlay ];
        };
      in
      {
        packages.${system} = {
          default = pkgs.claude-code;
          claude-code = pkgs.claude-code;
        };

        apps.${system} = {
          default = {
            type = "app";
            program = "${pkgs.claude-code}/bin/claude";
          };
          claude-code = {
            type = "app";
            program = "${pkgs.claude-code}/bin/claude";
          };
        };

        devShells.${system}.default = pkgs.mkShell {
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
