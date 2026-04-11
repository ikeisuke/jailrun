# Architecture

## Overview

jailrun provides multi-layered security for AI coding agents through three protection layers:

1. **OS Sandbox** — Kernel-enforced process isolation (Seatbelt on macOS, systemd-run on Linux)
2. **Credential Isolation** — Temporary credentials injected via environment variables
3. **Network Filtering** — Optional HTTPS CONNECT proxy with domain allowlisting

## Data Flow

```
jailrun <agent> [args...]
  │
  ├─ bin/jailrun              Entrypoint: subcommand dispatch
  │
  ├─ lib/agent-wrapper.sh     Common wrapper (binary resolution, arg rewriting)
  │    │
  │    ├─ lib/credential-guard.sh   Orchestrator (sources config → credentials → sandbox)
  │    │    │
  │    │    ├─ lib/config.sh              Config loading, validation, TOML migration
  │    │    │    ├─ lib/config-defaults.sh   Default values and template
  │    │    │    └─ lib/config.py            TOML parser (Python)
  │    │    │         ├─ lib/config_cli.py   CLI subcommand handler
  │    │    │         └─ lib/config_migrate.py  Shell→TOML migration
  │    │    │
  │    │    ├─ lib/credentials.sh         AWS credential extraction, GitHub PAT retrieval
  │    │    │    ├─ lib/aws.sh              AWS credential isolation
  │    │    │    └─ lib/platform/keychain-*.sh   OS-specific keychain access
  │    │    │
  │    │    └─ lib/sandbox.sh             Sandbox path lists, env-spec, exec script
  │    │         ├─ lib/platform/sandbox-darwin.sh   macOS Seatbelt profile generation
  │    │         ├─ lib/platform/sandbox-linux.sh    Linux systemd-run dispatch
  │    │         │    └─ lib/platform/sandbox-linux-systemd.sh   systemd property generation
  │    │         ├─ lib/platform/git-worktree.sh     Git worktree detection
  │    │         └─ lib/proxy.py           HTTPS CONNECT proxy (optional)
  │    │
  │    └─ exec <agent-binary> [args...]   Sandboxed execution
  │
  ├─ lib/token.sh             Token management (add/rotate/delete/list)
  └─ lib/ruleset.sh           GitHub repository ruleset management
```

## Sandbox Architecture

### sandbox.sh Sections

| Section | Responsibility |
|---------|---------------|
| Path lists | Build deny-read / allow-write path lists from defaults + user config |
| Platform backend | Load OS-specific sandbox implementation |
| Env-spec generation | Generate SET/UNSET directives for credential isolation |
| Exec script | Generate exec.sh with env setup + sandbox command |
| Proxy management | Start/stop HTTPS CONNECT proxy if enabled |
| Main entry point | Orchestrate sandbox setup, proxy, and exec |

### Double-Sandbox Prevention

When an agent calls another agent (e.g., Claude → Codex via shim), the `_CREDENTIAL_GUARD_SANDBOXED=1` environment variable prevents re-sandboxing. credential-guard.sh checks this variable and returns immediately if set.

### Platform Backends

| Platform | Backend | Mechanism |
|----------|---------|-----------|
| macOS | sandbox-darwin.sh | Seatbelt (sandbox-exec) with .sb profile |
| Linux | sandbox-linux-systemd.sh | systemd-run with security properties |

### Proxy (Optional)

When `proxy_enabled = true` in config, proxy.py starts as a background process:

- Only allows HTTPS CONNECT tunneling
- Domain allowlist filtering
- DNS rebinding protection (blocks private IP resolution)
- Blocks non-CONNECT methods (GET, POST, etc.)

## Configuration Architecture

```
~/.config/jailrun/config.toml    (user config, TOML format)
         │
         ├─ config.sh            Shell-level config loading
         │    reads via config.py (Python TOML parser)
         │
         ├─ config-cmd.sh        `jailrun config` subcommand handler
         │    delegates to config_cli.py
         │
         └─ config_migrate.py    Legacy shell config → TOML migration
```

### Config Loading Priority

1. Environment variables (highest priority)
2. `~/.config/jailrun/config.toml` (user config)
3. Defaults in `config-defaults.sh` (fallback)

## Security Model

### Credential Isolation

Sensitive credentials are never passed as command-line arguments (visible via `ps`). Instead:

1. `credentials.sh` extracts AWS creds and GitHub PAT into temp files
2. `sandbox.sh` generates an env-spec file with SET/UNSET directives
3. `exec.sh` applies env vars via `export` statements before exec

### Read-Denied Paths

Default blocked paths (kernel-enforced):
- `~/.aws` — AWS credentials
- `~/.config/gh` — GitHub CLI tokens
- `~/.gnupg` — GPG private keys
- `~/.ssh` — SSH private keys

### Keychain / Keyring Handling

| Platform | Mechanism |
|----------|-----------|
| macOS | Seatbelt allows `mach-lookup` for `com.apple.SecurityServer` and permits writes under `~/Library/Keychains` |
| Linux | D-Bus session bus socket made inaccessible |
