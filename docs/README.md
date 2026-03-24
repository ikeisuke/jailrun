# AI Agent Security Wrapper

Protects AI coding agents (Claude Code, Codex, Kiro CLI, Gemini CLI) from
abusing local credentials via multi-layered defense.

## Problem

Agents run in the user's terminal with full access to `~/.aws`, `~/.ssh`,
`~/.config/gh`, etc. Admin-level tokens can be leaked or misused.

## Architecture

```
Layer                           Mechanism                  Bypassable?
────────────────────────────────────────────────────────────────────
Layer 1: OS sandbox             Seatbelt / systemd-run     No (kernel-enforced)
Layer 2: Credential isolation   Temp credentials via env   No (set before exec)
Layer 3: Service-side limits    IAM Role / Fine-grained PAT No (server-side)
Layer 4: Tool-specific config   permissions.deny / hooks   Low-Med (AI judgment)
```

## File Structure

```
bin/
└── jailrun                  # entrypoint (subcommand dispatch)

lib/
├── credential-guard.sh      # orchestrator (sources config/credentials/sandbox)
├── config.sh                # config loading, validation, migration
├── credentials.sh           # temp dir, AWS credential extraction, GitHub token
├── sandbox.sh               # sandbox path lists, exec script generation
├── agent-wrapper.sh         # common wrapper (binary resolution, codex arg rewrite)
├── aws.sh                   # AWS credential isolation
├── token.sh                 # token management (add, rotate, delete, list)
├── ruleset.sh               # GitHub repository ruleset management
├── shims/
│   └── codex                # delegates to `jailrun codex` inside sandbox
└── platform/
    ├── keychain-darwin.sh   # macOS Keychain token retrieval
    ├── keychain-linux.sh    # Linux GNOME Keyring token retrieval
    ├── sandbox-darwin.sh    # macOS Seatbelt sandbox profile generation
    ├── sandbox-linux.sh     # Linux systemd-run property generation
    └── git-worktree.sh      # git worktree detection (shared)

~/.config/jailrun/
└── config                   # machine-specific config (not tracked, auto-generated)
```

## Pipeline

```
jailrun <agent>
  → config.sh          load/generate ~/.config/jailrun/config
  → credentials.sh     extract AWS creds + GitHub PAT into temp files
  → sandbox.sh         build deny/allow path lists, generate exec.sh
  → exec               sandbox-exec / systemd-run with isolated env
```

## Protection Levels by Tool

| Protection | Claude Code | Codex | Kiro CLI | Gemini CLI |
|------------|------------|-------|----------|------------|
| Credential isolation | Yes | Yes | Yes | Yes |
| OS sandbox | Seatbelt (*) | Seatbelt / systemd-run | Seatbelt / systemd-run | Seatbelt / systemd-run |
| Write restriction | Seatbelt whitelist | Seatbelt / systemd-run | Seatbelt / systemd-run | Seatbelt / systemd-run |
| Network restriction | No | Built-in (blocked by default) | No | No |

> **(*) Claude Code note**: sandbox-exec wraps the Claude process, but child
> processes (Bash tool) may not inherit the sandbox. Consider supplementing
> with Claude Code's `permissions.deny` and `PreToolUse` hooks (user-configured,
> not shipped by this repo).

## Setup

### 1. Install

```bash
make install                        # installs to ~/.local
make install PREFIX=/usr/local      # installs to /usr/local
```

### 2. First run

```bash
jailrun claude  # or codex, gemini, kiro-cli, kiro-cli-chat
```

On first run, `~/.config/jailrun/config` is auto-generated and the process
exits, prompting you to review the config.

### 3. Edit config

```bash
vi ~/.config/jailrun/config
```

```bash
# allowed AWS profiles (space-separated)
ALLOWED_AWS_PROFILES="dev staging"

# default AWS profile
DEFAULT_AWS_PROFILE="dev"

# token name registered via `jailrun token`
GH_KEYCHAIN_SERVICE="github:classic"
```

Binary paths are resolved automatically via `command -v` with PATH cleaning
(no manual configuration needed).

### 4. Set up GitHub PAT

See [github-pat-setup.md](./github-pat-setup.md).
Fine-grained and Classic PATs can be stored under separate Keychain service names.

### 5. Linux/WSL2

Uses systemd-run (no extra install if systemd is available):

```bash
# check if systemd is active in WSL2
systemctl --user status
```

GitHub tokens are managed via `secret-tool` (GNOME Keyring):

```bash
sudo apt install libsecret-tools gnome-keyring    # Ubuntu/Debian
jailrun token add --name github:classic
```

If `secret-tool` is not installed, jailrun runs without GitHub PAT (WARN shown).

## Usage

```bash
# normal launch (protected with configured profile)
jailrun claude
jailrun codex
jailrun kiro-cli
jailrun gemini

# use a different AWS profile temporarily (must be in allowlist)
AGENT_AWS_PROFILE=staging jailrun claude

# load multiple profiles (must be in allowlist)
AGENT_AWS_PROFILES="dev staging" jailrun claude

# inherit shell's AWS_PROFILE
AWS_PROFILE=dev jailrun claude
```

### Repository Rulesets

Create GitHub repository rulesets to enforce branch and tag protection:

```bash
# auto-detect repo from git remote, create rulesets
jailrun ruleset

# specify repo explicitly
jailrun ruleset owner/repo

# preview without applying
jailrun ruleset --dry-run
jailrun ruleset --dry-run owner/repo
```

**Rulesets created:**

| Ruleset | Target | Rules |
|---------|--------|-------|
| `jailrun-branch-protection` | Default branch | Require PR + 1 approval, block force-push |
| `jailrun-tag-protection` | All tags | Prevent tag deletion |

**Prerequisites:**
- `gh` CLI installed and authenticated (`gh auth login`)
- Admin access to the target repository

The command is idempotent: existing rulesets with the same name are skipped.

### AWS Profile Priority

```
AGENT_AWS_PROFILE  →  AWS_PROFILE  →  DEFAULT_AWS_PROFILE in config
(highest)             (shell env)      (fallback)
```

## Sandbox Protection

### Read-Denied Paths

These directories are blocked at kernel level:

| Path | Contents |
|------|----------|
| `~/.aws` | AWS credentials, SSO cache, config |
| `~/.config/gh` | GitHub CLI tokens |
| `~/.gnupg` | GPG private keys |
| `~/.ssh` | SSH private keys, known_hosts |

Additional paths can be added via `SANDBOX_EXTRA_DENY_READ` in config.

> **SSH→HTTPS conversion**: git SSH URLs (`git@github.com:` / `ssh://git@github.com/`)
> are rewritten to HTTPS via `GIT_CONFIG` env vars, authenticated via `GIT_ASKPASS`
> with `GH_TOKEN`. This allows git operations without SSH keys.
> On Linux (systemd-run), env vars are passed explicitly via `-E` flags.

### Sandbox Detection (Nesting Prevention)

When an agent calls another agent (e.g., Claude → Codex), double-sandboxing
is prevented by the `_CREDENTIAL_GUARD_SANDBOXED=1` env var, which is set
in the generated exec.sh and inherited by all child processes.

### Codex Built-in Sandbox

Codex applies its own sandbox-exec, which conflicts with jailrun's Seatbelt.
The built-in sandbox is disabled via two paths:

**1. Direct invocation** (`jailrun codex`): `agent-wrapper.sh` rewrites args:

| Subcommand | Method |
|------------|--------|
| `exec` / `e` | Inserts `-s danger-full-access` after subcommand |
| `review` | Inserts `-c 'sandbox_mode="danger-full-access"'` after subcommand |

User-provided `-s` / `--sandbox` is overwritten to `danger-full-access` with a warning.

**2. Indirect invocation** (e.g., Claude → Codex from within sandbox):
`lib/shims/codex` is injected into PATH. The shim simply runs `exec jailrun codex "$@"`,
which re-enters the jailrun flow. The `_is_sandboxed` check detects the existing
sandbox and skips re-sandboxing, while still rewriting Codex args.

## Claude Code Supplementary Protection

> **Note**: The following are **user-configured recommendations**, not shipped
> by this repository. They supplement Layer 1-3 protections.

### permissions.deny / permissions.ask

Configure in Claude Code's `settings.json`:

- **deny**: Read/Bash for `~/.aws`, `~/.ssh`; direct `aws sso get-role-credentials` etc.
- **ask**: Bash commands containing `~/.aws`, `~/.config/gh` (confirmation dialog)

### PreToolUse hook

Block all tool execution if sandbox is not applied:

```json
"PreToolUse": [{
  "hooks": [{
    "type": "command",
    "command": "if [ -r ~/.ssh ]; then echo 'Sandbox not applied. Relaunch via jailrun claude' >&2; exit 2; fi"
  }]
}]
```

- `~/.ssh` readable → sandbox not applied → exit 2 (block)
- `~/.ssh` unreadable → sandbox applied → exit 0 (allow)

> Alternatively, check the env var:
> `[ "${_CREDENTIAL_GUARD_SANDBOXED:-}" != "1" ]`.

## Verification

Inside the agent, try the following. `Operation not permitted` means success:

```
cat ~/.aws/config
```

## Troubleshooting

### "AWS credential export failed"

SSO session expired. Re-login:

```bash
aws sso login --profile <profile-name>
```

### Sandbox Debugging

Launch with `AGENT_SANDBOX_DEBUG=1` to:
- Disable write restrictions (read denials remain active)
- Print exec command to stderr

Use `find -newer` to identify write targets outside the whitelist:

```bash
# Terminal 1: create marker
touch /tmp/before-agent

# Terminal 2: launch in debug mode and reproduce
AGENT_SANDBOX_DEBUG=1 jailrun claude

# Terminal 1: check write targets after operation
find ~ -maxdepth 4 -newer /tmp/before-agent \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -not -path '*/Library/Logs/*' \
  -not -path '*/.claude/projects/*' \
  2>/dev/null | sort
```

Add discovered paths to `SANDBOX_EXTRA_ALLOW_WRITE` or
`SANDBOX_EXTRA_ALLOW_WRITE_FILES` in `~/.config/jailrun/config`.

### Agent won't start / behaves oddly

Sandbox write restrictions may be the cause. Isolate:

```bash
# 1. launch the binary directly to confirm sandbox is the cause
/opt/homebrew/bin/claude

# 2. if it works, use debug mode to find blocked writes
AGENT_SANDBOX_DEBUG=1 jailrun claude
```

### Bypass the wrapper

Call the binary directly:

```bash
/opt/homebrew/bin/claude
```
