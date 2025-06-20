# claude-code-nix

Nix package for [Claude Code](https://claude.ai/code) - AI coding assistant in your terminal.

## Why this package?

When using development environment managers like devenv, asdf, or nvm, globally installed npm packages can become unavailable or incompatible. This Nix package bundles Claude Code with its own Node.js runtime, ensuring it's always available regardless of your project's Node.js version.

## Installation

### Using Nix Flakes

Add to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    claude-code.url = "github:sadjow/claude-code-nix";
  };

  outputs = { self, nixpkgs, claude-code, ... }: {
    # Use as an overlay
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        {
          nixpkgs.overlays = [ claude-code.overlays.default ];
          environment.systemPackages = [ pkgs.claude-code ];
        }
      ];
    };
  };
}
```

### Using Home Manager

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    claude-code.url = "github:sadjow/claude-code-nix";
  };

  outputs = { self, nixpkgs, home-manager, claude-code, ... }: {
    homeConfigurations."username" = home-manager.lib.homeManagerConfiguration {
      modules = [
        {
          nixpkgs.overlays = [ claude-code.overlays.default ];
          home.packages = [ pkgs.claude-code ];
        }
      ];
    };
  };
}
```

### Direct Installation

```bash
# Run directly
nix run github:sadjow/claude-code-nix

# Install to profile
nix profile install github:sadjow/claude-code-nix
```

## Using Cachix

To avoid building from source, you can use our Cachix cache:

```nix
{
  nix.settings = {
    substituters = [ "https://claude-code.cachix.org" ];
    trusted-public-keys = [ "claude-code.cachix.org-1:<PUBLIC-KEY>" ];
  };
}
```

## Development

```bash
# Clone the repository
git clone https://github.com/sadjow/claude-code-nix
cd claude-code-nix

# Build the package
nix build

# Run tests
nix run .#claude-code -- --version

# Enter development shell
nix develop
```

## Updating Claude Code Version

To update to a newer version of Claude Code:

1. Edit `package.nix` and change the `version` field
2. Build and test locally
3. Submit a pull request

## License

The Nix packaging is MIT licensed. Claude Code itself is proprietary software by Anthropic.