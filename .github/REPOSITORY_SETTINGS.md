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

### Personal Access Token (PAT) for Auto-Tagging

A PAT is required to trigger the auto-tagging workflow after version updates are merged.

1. Go to https://github.com/settings/personal-access-tokens
2. Generate a new fine-grained token:
   - Name: "claude-code-nix auto-merge"
   - Repository access: Only select repositories → sadjow/claude-code-nix
   - Permissions: Contents → Read and write
3. Add as repository secret:
   - Navigate to Settings → Secrets and variables → Actions
   - Create secret named `PAT_TOKEN` with the token value

This enables the auto-merge to trigger the `create-version-tag.yml` workflow.

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

