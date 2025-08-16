# claude-code-nix

Always up-to-date Nix package for [Claude Code](https://claude.ai/code) - AI coding assistant in your terminal.

**🚀 Automatically updated daily** to ensure you always have the latest Claude Code version.

## Why this package?

When using development environment managers like devenv, asdf, or nvm, globally installed npm packages can become unavailable or incompatible. This Nix package bundles Claude Code with its own Node.js runtime, ensuring it's always available regardless of your project's Node.js version.

### Always Up-to-Date

While Claude Code may be available in nixpkgs, it's not always using the latest version. This repository:

- **Automatically checks for new Claude Code versions daily** via GitHub Actions
- **Creates pull requests immediately** when updates are available
- **Ensures you always have access to the latest features** without waiting for nixpkgs updates
- **Provides pre-built binaries via Cachix** for instant installation

### Key Features

- **Bundled Node.js Runtime**: Always works regardless of project-specific Node.js versions
- **Permission Persistence**: Maintains Claude settings and directory permissions across nix updates
- **Stable Binary Path**: Uses `~/.local/bin/claude` symlink to prevent macOS permission resets
- **Home Manager Integration**: Automatically preserves `.claude.json` and `.claude/` directory during switches

## Quick Start

### Step 1: Enable Cachix (Recommended)

To get instant installation with pre-built binaries:

```bash
# Install cachix if you haven't already
nix-env -iA cachix -f https://cachix.org/api/v1/install

# Configure the claude-code cache
cachix use claude-code
```

Alternatively, add to your Nix configuration:

```nix
{
  nix.settings = {
    substituters = [ "https://claude-code.cachix.org" ];
    trusted-public-keys = [ "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk=" ];
  };
}
```

### Step 2: Install Claude Code

#### Direct Installation (Simplest)

```bash
# Run directly
nix run github:sadjow/claude-code-nix

# Or install to profile
nix profile install github:sadjow/claude-code-nix
```

#### Using Nix Flakes

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

#### Using Home Manager (Best for macOS)

For automatic permission preservation on macOS:

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

To enable automatic permission preservation, create `~/.config/nixpkgs/home-manager/modules/claude-code.nix`:

```nix
{ config, pkgs, lib, ... }:

{
  # Create stable binary path
  home.activation.claudeStableLink = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p $HOME/.local/bin
    rm -f $HOME/.local/bin/claude
    ln -s ${pkgs.claude-code}/bin/claude $HOME/.local/bin/claude
  '';

  # Add to PATH
  home.sessionPath = [ "$HOME/.local/bin" ];
  
  # Preserve config during switches
  home.activation.preserveClaudeConfig = lib.hm.dag.entryBefore ["writeBoundary"] ''
    [ -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json" "$HOME/.claude.json.backup" || true
  '';
  
  home.activation.restoreClaudeConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    [ -f "$HOME/.claude.json.backup" ] && [ ! -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json.backup" "$HOME/.claude.json" || true
  '';
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
nix run . -- --version

# Check for version updates
./scripts/update-version.sh --check

# Enter development shell
nix develop
```

## Updating Claude Code Version

### Automated Updates

This repository uses GitHub Actions to automatically check for new Claude Code versions daily. When a new version is detected:

1. A pull request is automatically created with the version update
2. The tarball hash is automatically calculated
3. Tests run on both Ubuntu and macOS to verify the build
4. The PR auto-merges if all checks pass

The automated update workflow runs:
- Daily at midnight UTC
- On manual trigger via GitHub Actions UI

### Manual Updates

#### Using the Update Script (Recommended)

```bash
# Check for updates
./scripts/update-version.sh --check

# Update to latest version
./scripts/update-version.sh

# Update to specific version
./scripts/update-version.sh --version 1.0.82

# Show help
./scripts/update-version.sh --help
```

The script automatically:
- Updates the version in `package.nix`
- Fetches and calculates the tarball hash
- Updates `flake.lock` with latest nixpkgs
- Verifies the build succeeds

#### Manual Process

If you prefer to update manually:

1. Edit `package.nix` and change the `version` field
2. Get the new tarball hash: `nix-prefetch-url https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-VERSION.tgz`
3. Update the `sha256` field in `package.nix` with the new hash
4. Build and test locally: `nix build && ./result/bin/claude --version`
5. Update `flake.lock`: `nix flake update`
6. Submit a pull request

## Troubleshooting

### Known Issues

#### "Claude symlink points to invalid binary" warning

When running `claude /status`, you may see a warning: "Claude symlink points to invalid binary: /nix/store/.../bin/claude"

**This is a false positive and can be safely ignored.** The warning occurs because Claude Code's validation expects a large binary file (>10MB), but Nix packages Claude as a wrapper script that launches Node.js with the actual CLI code. This is standard practice in Nix packaging and everything works correctly despite the warning.

### Claude asks for permissions after every update

This package includes fixes for permission persistence. If you're still experiencing issues:

1. Ensure you're using the Home Manager configuration with the claude-code module
2. Check that `~/.local/bin/claude` symlink exists
3. Run `claude` from `~/.local/bin/claude` instead of the nix store path
4. Your `.claude.json` and `.claude/` directory should be preserved across updates

### Manual permission reset

If you need to reset Claude's permissions:

```bash
rm -rf ~/.claude ~/.claude.json
```

## License

The Nix packaging is MIT licensed. Claude Code itself is proprietary software by Anthropic.
