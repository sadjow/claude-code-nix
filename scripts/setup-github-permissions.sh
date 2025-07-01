#!/usr/bin/env bash
set -euo pipefail

# Script to configure GitHub repository settings for automated updates
# This enables GitHub Actions to create pull requests

echo "Configuring GitHub repository settings..."

# Get the repository name from git remote
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "Repository: $REPO"

# Enable GitHub Actions to create and approve pull requests
echo "Enabling GitHub Actions to create pull requests..."

# Note: The workflow permissions setting cannot be directly set via the API
# We need to use the GitHub UI for this specific setting
# However, we can provide clear instructions

cat << EOF

================================================================
MANUAL CONFIGURATION REQUIRED
================================================================

To complete the setup, you need to manually configure the following in GitHub:

1. Go to: https://github.com/$REPO/settings/actions

2. Scroll down to "Workflow permissions"

3. Select: "Read and write permissions"

4. Check: "Allow GitHub Actions to create and approve pull requests"

5. Click "Save"

This will allow the automated update workflow to create pull requests.

================================================================

After completing these steps, you can test the workflow by running:
  gh workflow run "Update Claude Code Version"

EOF

# Create a settings documentation file
echo "Creating settings documentation..."
cat > .github/REPOSITORY_SETTINGS.md << 'EOF'
# Repository Settings Configuration

This repository requires specific GitHub settings to enable automated updates.

## Required Settings

### GitHub Actions Permissions

1. Navigate to Settings → Actions → General
2. Under "Workflow permissions":
   - Select **"Read and write permissions"**
   - Check **"Allow GitHub Actions to create and approve pull requests"**
3. Click Save

These settings allow the `update-claude-code.yml` workflow to:
- Modify files in the repository
- Create pull requests for version updates
- Update the flake.lock file

## Verification

After configuring the settings, you can verify the workflow works by:

```bash
# Manually trigger the update workflow
gh workflow run "Update Claude Code Version"

# Check the workflow status
gh run list --workflow="Update Claude Code Version"
```

## Troubleshooting

If you see the error "GitHub Actions is not permitted to create or approve pull requests":
- Ensure the settings above are properly configured
- The repository must not have branch protection rules that prevent GitHub Actions from creating PRs
- The workflow uses the built-in `GITHUB_TOKEN` which is automatically provided

EOF

echo "✅ Setup script created!"
echo "✅ Documentation created at .github/REPOSITORY_SETTINGS.md"