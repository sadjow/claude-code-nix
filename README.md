# claude-code-nix

Always up-to-date Nix package for [Claude Code](https://claude.ai/code) - AI coding assistant in your terminal.

**🚀 Automatically updated hourly** to ensure you always have the latest Claude Code version.

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
| **Version Pinning** | ⚠️ Manual | ✅ Channel-based | ✅ Git tags (v2.0.76, v2, latest) |
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

### Fastest Installation (Try it now!)

```bash
# Run Claude Code directly without installing
nix run github:sadjow/claude-code-nix
```

### Install to Your System

```bash
# Install to your profile (survives reboots)
nix profile install github:sadjow/claude-code-nix
```

### Optional: Enable Binary Cache for Faster Installation

To download pre-built binaries instead of compiling:

```bash
# Install cachix if you haven't already
nix-env -iA cachix -f https://cachix.org/api/v1/install

# Configure the claude-code cache
cachix use claude-code
```

Or add to your Nix configuration:

```nix
{
  nix.settings = {
    substituters = [ "https://claude-code.cachix.org" ];
    trusted-public-keys = [ "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk=" ];
  };
}
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

#### Using Home Manager

With Home Manager, add to your configuration:

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

## Version Pinning

Pin to specific Claude Code versions using git refs:

### Available Tags

| Tag | Example | Behavior |
|-----|---------|----------|
| `vX.Y.Z` | `v2.0.76` | Exact version (immutable) |
| `vX` | `v2` | Latest in major series (updates automatically) |
| `latest` | `latest` | Always newest version (updates automatically) |

### Usage Examples

```bash
# Always latest (default)
nix run github:sadjow/claude-code-nix

# Pin to exact version
nix run github:sadjow/claude-code-nix?ref=v2.0.76

# Track latest v2.x (auto-updates)
nix run github:sadjow/claude-code-nix?ref=v2

# Track latest v1.x (stays at v1.0.128)
nix run github:sadjow/claude-code-nix?ref=v1
```

### In Flake Inputs

```nix
{
  inputs = {
    # Always latest
    claude-code.url = "github:sadjow/claude-code-nix";

    # Pin to exact version
    claude-code.url = "github:sadjow/claude-code-nix?ref=v2.0.76";

    # Track major version
    claude-code.url = "github:sadjow/claude-code-nix?ref=v2";
  };
}
```

All versions from v1.0.35 onwards are tagged.

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
5. Version tags are automatically created (`vX.Y.Z`, `vX`, `latest`)

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

### Claude asks for permissions after every update (macOS)

On macOS, Claude Code may ask for permissions after each Nix update because the binary path changes. To fix this:

1. Create a stable symlink: `ln -s $(which claude) ~/.local/bin/claude`
2. Add `~/.local/bin` to your PATH
3. Always run `claude` from `~/.local/bin/claude`
4. Your `.claude.json` and `.claude/` directory will be preserved

### Manual permission reset

If you need to reset Claude's permissions:

```bash
rm -rf ~/.claude ~/.claude.json
```

## Alternatives

### Official Native Install

In late 2025, Anthropic introduced an official native install:

```bash
curl -fsSL https://claude.ai/install.sh | sh
```

This downloads a self-contained binary bundled with Bun runtime.

#### Trade-offs

| Aspect | Official Native Install | This Nix Flake |
|--------|------------------------|----------------|
| **Simplicity** | ✅ One command | Requires Nix |
| **Latest Version** | ⚠️ Can lag behind npm | ✅ Hourly updates |
| **Runtime** | Bun | Node.js 22 LTS |
| **Version Pinning** | ❌ No | ✅ Git tags |
| **Rollback** | ❌ Manual | ✅ `nix profile rollback` |
| **Declarative** | ❌ No | ✅ NixOS/Home Manager |
| **Windows** | Via WSL | Via WSL |

**Choose official native install if**: You want the simplest setup or don't use Nix.

**Choose this flake if**: You use NixOS/Home Manager, need version pinning, want the latest version, or prefer declarative configuration.

## License

The Nix packaging is MIT licensed. Claude Code itself is proprietary software by Anthropic.
