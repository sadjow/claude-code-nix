# Repository Settings Configuration

This repository requires specific GitHub settings to enable automated updates.

## Required Settings

### GitHub Actions Permissions

1. Navigate to Settings → Actions → General
2. Under "Workflow permissions":
   - Select **"Read and write permissions"**
   - Check **"Allow GitHub Actions to create and approve pull requests"**
3. Click Save

### Auto-Merge Settings

1. Navigate to Settings → General
2. Under "Pull Requests":
   - Check **"Allow auto-merge"**
3. Click Save

These settings allow the `update-claude-code.yml` workflow to:
- Modify files in the repository
- Create pull requests for version updates
- Update the flake.lock file
- Automatically merge PRs when all checks pass

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

