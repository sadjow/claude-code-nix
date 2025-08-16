# claude-code-nix

Always up-to-date Nix package for [Claude Code](https://claude.ai/code) - AI coding assistant in your terminal.

**🚀 Automatically updated daily** to ensure you always have the latest Claude Code version.

## Why this package?

### Primary Goal: Always Up-to-Date Claude Code for Nix Users

While both this flake and upstream nixpkgs provide Claude Code as a Nix package, this flake focuses on:

1. **Immediate Updates**: New Claude Code versions available within 1 hour of release
2. **Dedicated Maintenance**: Focused repository for quick fixes when Claude Code changes
3. **Flake-First Design**: Direct flake usage with Cachix binary cache
4. **Custom Wrapper Control**: Ready to adapt when Claude Code adds new validations or requirements
5. **Node.js 22 LTS**: Latest long-term support version for better performance and security

### Why Not Just Use npm Global?

While `npm install -g @anthropic-ai/claude-code` works, it has critical limitations:
- **Disappears on Node.js Switch**: When projects use different Node.js versions (via asdf/nvm), Claude Code becomes unavailable
- **Must Reinstall Per Version**: Need to install Claude Code separately for each Node.js version
- **Not Declarative**: Can't be managed in your Nix configuration
- **Not Reproducible**: Different Node.js versions can cause inconsistencies
- **Outside Nix**: Doesn't integrate with Nix's dependency management

**Example Problem**: You're working on a legacy project that uses Node.js 16 via asdf. When you switch to that project, your globally installed Claude Code (from Node.js 22) disappears from your PATH. Both this flake and upstream nixpkgs solve this by bundling Node.js with Claude Code.

### The Reality of nixpkgs Updates

While nixpkgs provides Claude Code, the update cycle can be slow:
- Pull requests can take days to weeks for review and merge
- Updates depend on maintainer availability
- You're tied to your nixpkgs channel's update schedule
- Emergency fixes for breaking changes can be delayed

### Our Approach: Dedicated Flake Repository

This repository provides:

- **Hourly Automated Updates**: GitHub Actions checks for new versions every hour
- **Instant Availability**: Updates are automatically built and cached to Cachix
- **Quick Fixes**: When Claude Code breaks or adds new requirements, we can fix immediately
- **Node.js 22 LTS**: We control the runtime version (upstream locked to Node.js 20)
- **Future Flexibility**: Prepared to test alternative runtimes like Bun

### Why Not Just Use Upstream nixpkgs?

While Claude Code exists in nixpkgs, our approach offers specific advantages:

1. **Always Latest Version**: Hourly automated checks vs waiting for nixpkgs PR reviews and merges
2. **Node.js Version Control**: We use Node.js 22 LTS (upstream is locked to Node.js 20 with no override option)
3. **Flake with Binary Cache**: Direct flake usage with Cachix means instant installation
4. **Custom Package Implementation**: Full control over the build process for future enhancements (e.g., Bun runtime)
5. **Dedicated Repository**: Focused maintenance without the complexity of nixpkgs contribution process

### Comparison Table

| Feature | npm global | nixpkgs upstream | This Flake |
|---------|------------|------------------|------------|
| **Latest Version** | ✅ Always | ❌ Delayed | ✅ Hourly checks |
| **Node.js Version** | ⚠️ Per Node install | 🔒 Node.js 20 | ✅ Node.js 22 LTS |
| **Survives Node Switch** | ❌ Lost on switch | ✅ Always available | ✅ Always available |
| **Binary Cache** | ❌ None | ✅ NixOS cache | ✅ Cachix |
| **Declarative Config** | ❌ None | ✅ Yes | ✅ Yes |
| **Version Pinning** | ⚠️ Manual | ✅ Channel-based | ✅ Flake lock |
| **Update Frequency** | ✅ Immediate | ⚠️ Weeks | ✅ < 1 hour |
| **Reproducible** | ❌ No | ✅ Yes | ✅ Yes |
| **Sandbox Builds** | ❌ N/A | ✅ Yes | ✅ Yes |

### Key Features

- **Always Up-to-Date**: Automated hourly checks and updates via GitHub Actions
- **Pre-built Binaries**: Cachix provides instant installation without compilation
- **Flake-native**: Modern Nix flake for composable, reproducible deployments
- **Home Manager Example**: Sample configuration for permission persistence on macOS
- **Custom Build Process**: Optimized for Claude Code's specific requirements

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

## Technical Details

### Package Architecture

Our custom `package.nix` implementation:

1. **Pre-fetches npm tarball**: Uses Nix's Fixed Output Derivation (FOD) for reproducible, offline builds
2. **Bundles Node.js 22 LTS**: Ensures consistent runtime environment across all systems
3. **Custom wrapper script**: Handles PATH, environment variables, and Claude-specific requirements
4. **Sandbox compatible**: All network fetching happens during the FOD phase, not build phase

### Runtime Selection

Currently using **Node.js 22 LTS** because:
- Long-term stability and support until April 2027
- Better performance than Node.js 20 (upstream nixpkgs version)
- Latest LTS with all security updates
- Full control over version (upstream is hardcoded to Node.js 20)

### Future Enhancements

We're exploring support for alternative JavaScript runtimes:

- **Bun**: Potential performance improvements and faster startup times
- **Deno**: Enhanced security model and TypeScript support
- **Runtime selection**: Allow users to choose their preferred runtime via overlay options

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

This repository uses GitHub Actions to automatically check for new Claude Code versions every hour. When a new version is detected:

1. A pull request is automatically created with the version update
2. The tarball hash is automatically calculated
3. Tests run on both Ubuntu and macOS to verify the build
4. The PR auto-merges if all checks pass

The automated update workflow runs:
- Every hour (at the top of the hour)
- On manual trigger via GitHub Actions UI

This means new Claude Code versions are typically available in this flake within 30 minutes of being published to npm!

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
