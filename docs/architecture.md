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
  │    │         ├─ lib/proxy.py           HTTPS CONNECT proxy (optional)
  │    │         ├─ _start_deny_log()      Deny log collection (DEBUG, Darwin only)
  │    │         ├─ exec <agent-binary>    Sandboxed execution
  │    │         ├─ _stop_deny_log()       Stop deny log (DEBUG)
  │    │         └─ display deny log       Show deny events on stderr (DEBUG)
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
| Deny log hooks | Platform-specific deny event collection (Darwin: log stream, Linux: no-op) |
| Main entry point | Orchestrate sandbox setup, proxy, deny log, and exec |

#### Write Path Composition

The allow-write path list is composed of several categories with different
platform consumption models:

| Write allowance type | Darwin (Seatbelt) | Linux (systemd) |
|----------------------|-------------------|-----------------|
| Lock paths (`_SANDBOX_ALLOW_WRITE_LOCK_PATHS`) | `subpath` permission | `ReadWritePaths` |
| Single-file writes (`_SANDBOX_ALLOW_WRITE_FILES`) | `literal` permission | Not consumed |
| Regex patterns (`_SANDBOX_ALLOW_WRITE_REGEXES`) | `regex` permission | Not consumed (no regex support) |

### Double-Sandbox Prevention

When an agent calls another agent (e.g., Claude → Codex via shim), the `_CREDENTIAL_GUARD_SANDBOXED=1` environment variable prevents re-sandboxing. credential-guard.sh checks this variable and returns immediately if set.

### Platform Backends

| Platform | Backend | Mechanism |
|----------|---------|-----------|
| macOS | sandbox-darwin.sh | Seatbelt (sandbox-exec) with .sb profile |
| Linux | sandbox-linux-systemd.sh | systemd-run with security properties |

### Deny Log Architecture

Deny event logging follows an Optional Hook pattern. The orchestrator
(`sandbox.sh`) manages the lifecycle, while platform backends provide
the actual implementation or a no-op stub:

| Layer | Responsibility |
|-------|---------------|
| sandbox.sh (orchestrator) | Start/stop hooks in DEBUG mode, EXIT trap cleanup, stderr display at exit |
| sandbox-darwin.sh (backend) | `_start_deny_log()`: start `log stream` with Seatbelt predicate, `_stop_deny_log()`: kill process. Warns on stderr if `log stream` fails to start |
| sandbox-linux.sh (backend) | No-op (future extension point) |

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

| Path | Description |
|------|-------------|
| `~/.aws` | AWS credentials, SSO cache |
| `~/.config/gh` | GitHub CLI tokens |
| `~/.gnupg` | GPG private keys |
| `~/.ssh` | SSH private keys |
| `~/.config/gcloud` | Google Cloud SDK credentials |
| `~/.azure` | Azure CLI credentials |
| `~/.oci` | Oracle Cloud Infrastructure credentials |
| `~/.docker` | Docker registry auth tokens |
| `~/.kube` | Kubernetes cluster credentials |
| `~/.wrangler` | Cloudflare Wrangler (v1) tokens |
| `~/.config/wrangler` | Cloudflare Wrangler (v2+) tokens |
| `~/.fly` | Fly.io API tokens |
| `~/.config/netlify` | Netlify access tokens |
| `~/.config/vercel` | Vercel auth tokens |
| `~/.config/heroku` | Heroku API keys |
| `~/.terraform.d` | Terraform CLI tokens |
| `~/.vault-token` | HashiCorp Vault token |
| `~/.config/op` | 1Password CLI tokens |
| `~/.config/hub` | GitHub Hub (legacy) tokens |
| `~/.config/stripe` | Stripe CLI API keys |
| `~/.config/firebase` | Firebase CLI tokens |
| `~/.netrc` | HTTP credentials (curl, wget) |
| `~/.npmrc` | npm auth tokens |

Users can add custom paths via `sandbox_extra_deny_read` in config.

**Note**: On Linux (systemd-run), `InaccessiblePaths` requires the path to exist at sandbox startup. Paths created after startup are not protected.

### Keychain / Keyring Handling

| Platform | Mechanism |
|----------|-----------|
| macOS | Seatbelt allows `mach-lookup` for `com.apple.SecurityServer`; `~/Library/Keychains` write access controlled by `keychain_profile` setting |
| Linux | D-Bus session bus socket made inaccessible |

#### macOS Keychain Access Profiles (`keychain_profile`)

| Profile | `~/Library/Keychains` Writes | Use Case |
|---------|------------------------------|----------|
| `allow` (default) | Permitted (subpath) | In-sandbox auth and token refresh (e.g. `claude auth login`) |
| `deny` | Blocked | Authenticate outside sandbox first; cached tokens may still work |
| `read-cache-only` | Blocked (same as `deny`) | Semantic alias — indicates intent to use cached auth only |

**Technical background**: macOS SecurityServer (securityd) mediates Keychain operations. `file-read*` deny rules do not affect Keychain reads because SecurityServer reads DB files in its own process context. However, `file-write*` deny rules do block Keychain writes because SecurityServer writes to DB files under the sandboxed process's file-write policy. TLS certificate verification is unaffected as it uses `/Library/Keychains/System.keychain`.
