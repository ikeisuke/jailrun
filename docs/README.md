# AI Agent Security Wrapper — Detailed Reference

> For quick start, installation, and configuration, see the [main README](../README.md).

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

> For installation and basic configuration, see the [main README](../README.md).

Binary paths are resolved automatically via `command -v` with PATH cleaning
(no manual configuration needed).

Fine-grained and Classic PATs can be stored under separate Keychain service names.
See [github-pat-setup.md](./github-pat-setup.md) for details.

If `secret-tool` is not installed on Linux, jailrun runs without GitHub PAT (WARN shown).

## Usage

> For basic commands, see the [main README](../README.md#quick-start).

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
AGENT_AWS_PROFILES  →  AWS_PROFILE  →  DEFAULT_AWS_PROFILE in config
(highest)              (shell env)      (fallback)
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

### Keychain / Keyring Access

The sandbox treats OS credential stores differently by platform:

| Platform | Mechanism |
|----------|-----------|
| macOS | Seatbelt keeps `com.apple.SecurityServer` reachable and permits writes under `~/Library/Keychains` |
| Linux | D-Bus session bus socket made inaccessible via `InaccessiblePaths` |

On macOS, this is required for native TLS trust evaluation and for sandboxed
apps that refresh their own auth state through Keychain-backed storage.
Secrets are still protected by read-deny rules on sensitive files and by
injecting scoped credentials via environment variables before sandbox exec.

### Write Allowances

The sandbox permits writes to specific paths required by Claude Code's
lock and config update mechanisms:

| Path / Pattern | Platform | Purpose |
|----------------|----------|---------|
| `~/.claude.lock` | macOS + Linux | Lock directory for `~/.claude` (proper-lockfile) |
| `~/.claude.json.lock` | macOS + Linux | Lock directory for `~/.claude.json` (proper-lockfile) |
| `~/.claude.json.tmp.*` | macOS only | Atomic write temp file (Seatbelt regex) |

Lockfile paths are directories created by proper-lockfile next to their
target files. Both macOS (Seatbelt `subpath`) and Linux (systemd
`ReadWritePaths`) grant write access to these paths.

The atomic write regex pattern (`~/.claude.json.tmp.*`) is consumed only
by the macOS Seatbelt profile. Linux's systemd backend does not support
regex-based write permissions; target files are covered implicitly when
the working directory includes `$HOME`.

### Environment Variable Passthrough

By default, the sandbox strips sensitive environment variables. To pass custom
variables through to the sandboxed process, set `SANDBOX_PASSTHROUGH_ENV` in
config (space-separated list of variable names):

```bash
SANDBOX_PASSTHROUGH_ENV="ANTHROPIC_API_KEY OPENAI_API_KEY MY_CUSTOM_VAR"
```

Only variables that are set and non-empty in the current shell are passed
through; unset or empty variables are silently skipped.

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

> For common issues, see the [main README](../README.md#troubleshooting).

### Seatbelt Deny Log (macOS)

When `AGENT_SANDBOX_DEBUG=1` is set, jailrun automatically collects
Seatbelt deny events during execution and displays them on stderr at exit.

```bash
AGENT_SANDBOX_DEBUG=1 jailrun claude
```

Deny events are logged to `$TMPDIR/jailrun-seatbelt-<PID>.log` (PID-based
filename prevents conflicts during parallel runs). On exit, if the log file
is non-empty, its contents are printed between `=== Seatbelt deny log ===`
markers on stderr.

This helps identify which file-system operations the sandbox blocked,
making it easier to diagnose issues like token refresh failures or
unexpected permission errors.

> **Note**: This feature is macOS-only. Linux does not currently support
> deny event logging.

### Advanced: Finding Blocked Write Paths

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
`SANDBOX_EXTRA_ALLOW_WRITE_FILES` in `~/.config/jailrun/config.toml`.
