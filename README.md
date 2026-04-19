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
5. **Native Binary**: Self-contained binary with no runtime dependencies

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

### Why Not Just Use Upstream nixpkgs?

While Claude Code exists in nixpkgs, our approach offers specific advantages:

1. **Always Latest Version**: Hourly automated checks vs waiting for nixpkgs PR reviews and merges
2. **Native Binary**: Self-contained ~180MB binary with no runtime dependencies
3. **Flake with Binary Cache**: Direct flake usage with Cachix means instant installation
4. **Dedicated Repository**: Focused maintenance without the complexity of nixpkgs contribution process

### Comparison Table

| Feature | npm global | nixpkgs upstream | This Flake |
|---------|------------|------------------|------------|
| **Latest Version** | ✅ Always | ❌ Delayed | ✅ Hourly checks |
| **No Runtime Dependency** | ❌ Requires Node.js | ❌ Bundles Node.js | ✅ Self-contained native binary |
| **Survives Node Switch** | ❌ Lost on switch | ✅ Always available | ✅ Always available |
| **Binary Cache** | ❌ None | ✅ NixOS cache | ✅ Cachix |
| **Declarative Config** | ❌ None | ✅ Yes | ✅ Yes |
| **Exact Version Pinning** | ⚠️ Manual | ✅ Nixpkgs revision | ✅ Exact tags (`v2.1.71`) or commit SHAs |
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

## Standalone Installation (Without Home Manager)

If you're not using Home Manager or NixOS, here's the complete workflow for managing Claude Code with `nix profile`.

### Install

```bash
nix profile install github:sadjow/claude-code-nix
```

### Verify Installation

```bash
which claude
claude --version
```

### Update to Latest Version

```bash
# Update all flake-based packages
nix profile upgrade --all

# Or update only claude-code
nix profile upgrade '.*claude-code.*'
```

### Rollback

```bash
# Revert to previous profile state
nix profile rollback
```

### Uninstall

```bash
nix profile remove '.*claude-code.*'
```

### Troubleshooting PATH

If `claude` command is not found after installation, ensure `~/.nix-profile/bin` is in your PATH:

```bash
# Check if nix-profile/bin is in PATH
echo $PATH | tr ':' '\n' | grep nix-profile

# If not found, add to your shell config (~/.bashrc, ~/.zshrc, etc.)
export PATH="$HOME/.nix-profile/bin:$PATH"
```

For multi-user Nix installations, the PATH is typically configured by `/etc/profile.d/nix.sh` or similar. Ensure your shell sources this file.

### Using Overlay

```nix
{
  nixpkgs.overlays = [ claude-code.overlays.default ];
  # pkgs.claude-code is now available
}
```

### Custom Binary Name

You can override the binary name when building:

```nix
pkgs.claude-code.override { binName = "cc"; }
```

### Optional: Enable Binary Cache for Faster Installation

To download pre-built binaries instead of compiling:

```bash
# Install cachix if you haven't already
nix-env -iA cachix -f https://cachix.org/api/v1/install

# Configure the claude-code cache
cachix use claude-code
```

Using Cachix adds trust in this project's binary cache. If you prefer to verify builds locally from pinned source, skip Cachix and let Nix build locally instead.

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

## Version Pinning and Update Channels

Choose between immutable pins and moving update channels using git refs.

Only exact version tags such as `v2.1.71` or an exact commit SHA are true pins. `v2`, `latest`, and the bare `github:sadjow/claude-code-nix` reference are moving refs that intentionally follow newer commits over time.

### Available Refs

| Ref | Example | Behavior | Security Posture |
|-----|---------|----------|------------------|
| Exact version tag | `v2.1.71` | Immutable release tag | Best default for reproducible installs |
| Major tag | `v2` | Latest release in that major line | Moving channel, updates over time |
| `latest` tag | `latest` | Newest release | Moving channel, updates over time |
| Default branch | `github:sadjow/claude-code-nix` | Tracks repository `main` | Moving channel, fastest updates |

### Usage Examples

```bash
# Always latest from the default branch
nix run github:sadjow/claude-code-nix

# Pin to an exact immutable release
nix run github:sadjow/claude-code-nix?ref=v2.1.71

# Track latest v2.x (auto-updates)
nix run github:sadjow/claude-code-nix?ref=v2

# Track latest v1.x
nix run github:sadjow/claude-code-nix?ref=v1
```

### In Flake Inputs

```nix
{
  inputs = {
    # Always latest from the default branch
    claude-code.url = "github:sadjow/claude-code-nix";

    # Pin to an exact immutable release
    claude-code.url = "github:sadjow/claude-code-nix?ref=v2.1.71";

    # Track major version
    claude-code.url = "github:sadjow/claude-code-nix?ref=v2";
  };
}
```

All versions from v1.0.35 onwards are tagged.

If you use this repository as a flake input, your own `flake.lock` records the resolved commit. Exact tags and commit SHAs give the strongest control; moving refs such as `main`, `v2`, and `latest` only change when you update your own lock file.

## Security / Trust Model

This repository is optimized for fast Claude Code updates. That makes the trust model worth stating explicitly.

### What is verified today

- `package.nix` fetches the native binaries with fixed hashes, so a build only succeeds if the downloaded artifacts match the expected content.
- `flake.lock` pins the flake inputs for a given repository revision.
- The packaged binary disables Claude's built-in auto-updater, so updates happen through Nix rather than self-modification.
- CI builds and smoke-tests the package before update PRs land on `main`.

### What still requires trust

- Trusting this repo means trusting the maintainer account and the GitHub Actions update workflow that creates and auto-merges version bump PRs.
- The upstream artifacts still come from Anthropic's npm package and native binary distribution.
- Using the `claude-code` Cachix cache adds trust in this project's substituter key. Building locally avoids that extra trust layer.
- Moving refs such as `main`, `v2`, and `latest` trade stricter change control for convenience and freshness.

### Recommended setups

| Goal | Recommended Setup |
|------|-------------------|
| Highest assurance | Pin an exact commit SHA, skip Cachix, and build locally |
| Balanced default | Pin an exact version tag and optionally use Cachix for faster installs |
| Fastest updates | Track the default branch, `vX`, or `latest` and accept the faster update cadence |

### Forking

Forking is a valid option if you want to fully control update cadence, review upstream diffs yourself, or add additional policy checks before merging updates.

For most users, pinning an exact version tag is simpler and usually enough. A fork only meaningfully improves security if you also add your own review gate instead of automatically tracking upstream.

### Prefer Broader Review Over Speed?

If you prefer a slower update cadence with broader community review, upstream `nixpkgs` may be a better fit than this flake.

## Technical Details

### Package Architecture

- Downloads pre-built native binary from Anthropic's CDN
- Self-contained Bun single-file executable (~180MB)
- Uses `patchelf` on Linux for NixOS compatibility
- No external runtime dependencies
- Same binary as the official `claude.ai/install.sh` installer

### Environment Variables

The wrapper sets these environment variables:

| Variable | Purpose |
|----------|---------|
| `DISABLE_AUTOUPDATER=1` | Prevents auto-updates (managed by Nix) |
| `DISABLE_INSTALLATION_CHECKS=1` | Suppresses npm migration warning |
| `USE_BUILTIN_RIPGREP=0` | Uses the Nix-provided ripgrep |

### Package History

#### Removal of Node.js and Bun variants (v2.1.114)

Earlier releases of this flake shipped three variants: `claude-code` (native), `claude-code-node`, and `claude-code-bun`. The Node.js and Bun variants ran Claude Code from the npm package's JavaScript entry point (`cli.js`).

Starting with Claude Code `v2.1.113`, Anthropic restructured the `@anthropic-ai/claude-code` npm package. `cli.js` was removed. The npm package is now a thin wrapper whose `postinstall` copies a platform-specific native binary (shipped via `optionalDependencies`) over a placeholder, and whose `cli-wrapper.cjs` fallback spawns that same binary through a short-lived Node.js process.

As a result, the JS variants here broke: they tried to `exec node cli.js` and hit `MODULE_NOT_FOUND`. Keeping them alive would have meant re-implementing Anthropic's postinstall in Nix only to execute the same native binary the `native` variant already ships. The variants were removed in favor of the single, self-contained `claude-code` package.

If you were using `claude-code-node` or `claude-code-bun`, switch to `claude-code` and `claude`; behavior is identical.

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

This workflow is designed for freshness and build validation, not for manual review of every upstream release. New Claude Code versions are typically available in this flake within 30 minutes of being published to npm.

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
- Fetches native binary hashes for all platforms (darwin-arm64, darwin-x64, linux-x64, linux-arm64)
- Updates `flake.lock` with latest nixpkgs
- Verifies the build succeeds

#### Manual Process

If you prefer to update manually:

1. Edit `package.nix` and change the `version` field
2. For each platform, fetch the native binary hash: `nix-prefetch-url https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/VERSION/PLATFORM/claude`
3. Update the matching entry in the `nativeHashes` attribute set
4. Build and test locally: `nix build && ./result/bin/claude --version`
5. Update `flake.lock`: `nix flake update`
6. Submit a pull request

## Troubleshooting

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

Anthropic provides an official native installer:

```bash
curl -fsSL https://claude.ai/install.sh | sh
```

This downloads a self-contained binary bundled with Bun runtime.

#### Trade-offs

| Aspect | Official Native Install | This Nix Flake |
|--------|------------------------|----------------|
| **Simplicity** | ✅ One command | Requires Nix |
| **Same Binary** | ✅ Yes | ✅ Yes |
| **Latest Version** | ⚠️ Can lag behind npm | ✅ Hourly updates |
| **Version Pinning** | ❌ No | ✅ Git tags |
| **Rollback** | ❌ Manual | ✅ `nix profile rollback` |
| **Declarative** | ❌ No | ✅ NixOS/Home Manager |
| **Windows** | Via WSL | Via WSL |

**Choose official native install if**: You want the simplest setup or don't use Nix.

**Choose this flake if**: You use NixOS/Home Manager, want declarative configuration, and are comfortable choosing between exact pins and faster-moving update channels.

## License

The Nix packaging is MIT licensed. Claude Code itself is proprietary software by Anthropic.
