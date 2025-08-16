## Summary
- Fixes sandbox build failures by pre-fetching npm tarball as Fixed Output Derivation
- Maintains custom package.nix approach for full control
- Resolves issue #16 

## Problem
The previous implementation called `npm install` during the build phase, which requires network access and violates Nix sandbox restrictions. This caused builds to fail on NixOS and other sandboxed environments.

## Solution
- Pre-fetch the claude-code npm tarball using `fetchurl` (Fixed Output Derivation)
- Install from the local tarball instead of fetching from network during build
- Configure npm to work offline during installation

## Testing
- ✅ Builds successfully with `--option sandbox true`
- ✅ Version 1.0.81 installs and runs correctly
- ✅ No network access required during build phase

## Changes
- Added `fetchurl` to pre-fetch the npm package tarball
- Modified build phase to install from local tarball with `--offline` flag
- Added hash for version 1.0.81 tarball

Fixes #16