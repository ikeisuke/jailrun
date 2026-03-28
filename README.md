# jailrun

Security wrapper for AI coding agents — credential isolation + OS sandbox.

## Install

```bash
make install                        # installs to ~/.local/bin
make install PREFIX=/usr/local      # installs to /usr/local/bin
```

On first run, `~/.config/jailrun/config.toml` is auto-generated and the process exits, prompting you to review the config.

## Quick Start

```bash
# launch an agent inside the sandbox
jailrun claude
jailrun codex exec "fix the bug"
jailrun gemini
jailrun kiro-cli

# specify AWS profile(s)
AGENT_AWS_PROFILES=staging jailrun claude

# token management
jailrun token add --name github:fine-grained-myorg
jailrun token rotate --name github:fine-grained-myorg
jailrun token list

# repository ruleset protection
jailrun ruleset              # auto-detect from git remote
jailrun ruleset --dry-run    # preview without applying
```

### Supported Tools

Claude Code, Codex, Gemini CLI, Kiro CLI

### Protection Layers

| Layer | Mechanism | Bypassable? |
|-------|-----------|-------------|
| OS sandbox | Seatbelt (macOS) / systemd-run (Linux) | No (kernel-enforced) |
| Credential isolation | Temp credentials via env vars | No (set before exec) |
| Service-side limits | IAM Role / Fine-grained PAT | No (server-side) |

## Configuration Reference

Config file: `~/.config/jailrun/config.toml`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `ALLOWED_AWS_PROFILES` | list | `"default"` | Allowed AWS profiles (space-separated) |
| `DEFAULT_AWS_PROFILE` | string | `"default"` | Default AWS profile when none specified |
| `GH_TOKEN_NAME` | string | `"classic"` | Short token name (expanded to `jailrun:github:<name>`) |
| `SANDBOX_EXTRA_DENY_READ` | list | (empty) | Additional read-deny paths |
| `SANDBOX_EXTRA_ALLOW_WRITE` | list | (empty) | Additional write-allow directories |
| `SANDBOX_EXTRA_ALLOW_WRITE_FILES` | list | (empty) | Additional write-allow files |
| `SANDBOX_PASSTHROUGH_ENV` | list | (empty) | Env vars to pass through to sandbox |

### AWS Profile Priority

```
AGENT_AWS_PROFILES  →  AWS_PROFILE  →  DEFAULT_AWS_PROFILE in config
(highest)              (shell env)      (fallback)
```

### GitHub PAT Setup

See [docs/github-pat-setup.md](docs/github-pat-setup.md).

### Linux/WSL2

Uses systemd-run (no extra install if systemd is available). GitHub tokens are managed via `secret-tool` (GNOME Keyring):

```bash
sudo apt install libsecret-tools gnome-keyring    # Ubuntu/Debian
jailrun token add --name github:classic
```

## Troubleshooting

### "AWS credential export failed"

SSO session expired. Re-login:

```bash
aws sso login --profile <profile-name>
```

### Sandbox Debugging

Launch with `AGENT_SANDBOX_DEBUG=1` to disable write restrictions (read denials remain active) and print the exec command to stderr:

```bash
AGENT_SANDBOX_DEBUG=1 jailrun claude
```

### Agent won't start / behaves oddly

Sandbox write restrictions may be the cause. Isolate by calling the binary directly:

```bash
/opt/homebrew/bin/claude    # bypass the wrapper
```

### Verification

Inside the agent, confirm the sandbox is active:

```
cat ~/.aws/config    # should show "Operation not permitted"
```

## Details

For architecture, file structure, and advanced usage, see [docs/README.md](docs/README.md).

## License

MIT
