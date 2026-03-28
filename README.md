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
| `allowed_aws_profiles` | list | `["default"]` | Allowed AWS profiles |
| `default_aws_profile` | string | `"default"` | Default AWS profile when none specified |
| `gh_token_name` | string | `"classic"` | Short token name (expanded to `jailrun:github:<name>`) |
| `sandbox_extra_deny_read` | list | `[]` | Additional read-deny paths |
| `sandbox_extra_allow_write` | list | `[]` | Additional write-allow directories |
| `sandbox_extra_allow_write_files` | list | `[]` | Additional write-allow files |
| `sandbox_passthrough_env` | list | `[]` | Env vars to pass through to sandbox |

### Environment Variable Overrides

Some config keys can be overridden at runtime via environment variables:

| Env Var | Overrides | Example |
|---------|-----------|---------|
| `AGENT_AWS_PROFILES` | `allowed_aws_profiles` selection | `AGENT_AWS_PROFILES=staging jailrun claude` |
| `AWS_PROFILE` | `default_aws_profile` | `AWS_PROFILE=dev jailrun claude` |
| `GH_TOKEN_NAME` | `gh_token_name` | `GH_TOKEN_NAME=fine-grained jailrun claude` |
| `SANDBOX_PASSTHROUGH_ENV` | `sandbox_passthrough_env` | `SANDBOX_PASSTHROUGH_ENV="KEY1 KEY2" jailrun claude` |

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
