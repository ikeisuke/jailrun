# GitHub Fine-grained PAT Setup Guide

How to create and store a restricted GitHub token for AI agents
(Claude Code, Codex, Kiro CLI, Gemini CLI).

The security wrapper (`lib/credential-guard.sh`) retrieves tokens from
the system keychain and injects them into the agent's environment.
Register tokens with `jailrun token add --name <name>`.

## Why

- Tokens from `gh auth login` carry full permissions
- Org Owners, Repo Admins, and other privileged accounts can cause
  widespread damage if their tokens are leaked or misused
- Fine-grained PATs let you restrict scope to specific repositories
  and minimum permissions

## Prerequisites

### Linux / WSL2

Install `secret-tool` before registering tokens:

```bash
sudo apt install libsecret-tools gnome-keyring    # Ubuntu/Debian
```

If not installed, jailrun runs without GitHub PAT (a warning is shown).

### Branch Protection (required for Workflows permission)

If you plan to grant the **Workflows** permission to your PAT,
set up branch protection on target repositories first:

1. Repository **Settings > Branches > Add branch protection rule**
2. Branch name pattern: `main` (or `master`)
3. Enable:
   - **Require a pull request before merging**
   - **Require approvals** (at least 1 reviewer recommended)
   - **Do not allow bypassing the above settings**

This ensures the agent can create PRs that modify `.github/workflows`,
but cannot merge to main without review.

## 1. Create a Fine-grained PAT

### GitHub.com

1. Go to https://github.com/settings/tokens?type=beta
2. Click **Generate new token**
3. Configure:

| Field | Value |
|-------|-------|
| Token name | `ai-agent` (or a descriptive name) |
| Expiration | 30 days (short-lived, rotate regularly) |
| Resource owner | The account or **Organization** that owns the target repos |
| Repository access | **Only select repositories** (pick only what's needed) |

> **Resource owner**: Select the Organization if the repos you need
> belong to that org. The org may need to allow Fine-grained PATs
> under **Organization settings > Personal access tokens**.

4. Permissions (minimum required):

| Permission | Level | Purpose |
|-----------|-------|---------|
| Contents | Read and write | Read/write code |
| Pull requests | Read and write | Create PRs |
| Issues | Read-only | Reference issues |
| Metadata | Read-only | Auto-granted |
| Workflows | Read and write | Modify `.github/workflows` (requires branch protection) |

**Never grant these permissions**:
- Administration (repo settings, branch deletion)
- Actions (trigger/manage workflow runs)
- Organization administration
- Members (member management)

5. **Generate token** and copy it

### GitHub Enterprise

Additional considerations:

- If the Organization requires Fine-grained PAT approval, request it
  from an org admin
- Never grant `admin:org` or `admin:enterprise` scopes
- Consider creating separate tokens per Organization to limit blast
  radius

## 2. Store the Token

Use `jailrun token` to save to the system keychain (macOS Keychain /
Linux GNOME Keyring):

```bash
# Fine-grained PAT (recommended, one per org)
jailrun token add --name github:fine-grained-myorg

# Classic PAT (when broad repo access is needed)
jailrun token add --name github:classic
```

Token names are arbitrary. Recommended naming by Organization:

| Token name | Use case |
|-----------|----------|
| `github:fine-grained-myorg` | Fine-grained PAT for myorg (recommended) |
| `github:fine-grained-personal` | Fine-grained PAT for personal repos |
| `github:classic` | Classic PAT (all repos) |

### Switch Active Token

Set the active token in `~/.config/jailrun/config` (short name only):

```bash
GH_TOKEN_NAME="fine-grained-myorg"  # or classic
```

Override at runtime:

```bash
GH_TOKEN_NAME=fine-grained-myorg jailrun claude
```

### List Registered Tokens

```bash
jailrun token list
```

## 3. Token Rotation

Rotate tokens regularly (every 30 days recommended):

```bash
jailrun token rotate --name github:classic
jailrun token rotate --name github:fine-grained-myorg
```

Generate a new token on GitHub, then run the rotate command to update
the keychain entry.

## 4. Verify

```bash
# Launch via jailrun
jailrun claude

# Inside the agent, run:
# gh auth status → should show the Fine-grained PAT is active
```

## Troubleshooting

### "WARN: GitHub PAT not configured"

No token stored in keychain. Follow step 2 above.

### Permission denied errors

The PAT lacks required permissions. Edit the PAT on GitHub and add
the needed permission. Follow the principle of least privilege — only
add what's necessary.

### Cannot access Organization repositories

Check that the PAT's Resource owner is set to the correct Organization.
Verify that the Organization allows Fine-grained PATs (ask an org admin).
