# jailrun

Security wrapper for AI coding agents — credential isolation + OS sandbox.

## Supported Tools

Claude Code, Codex, Gemini CLI, Kiro CLI

## Install

```bash
make install                        # installs to ~/.local/bin
make install PREFIX=/usr/local      # installs to /usr/local/bin
```

Config is auto-generated on first run at `~/.config/jailrun/config`.

## Usage

```bash
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
```

## Protection Layers

| Layer | Mechanism | Bypassable? |
|-------|-----------|-------------|
| OS sandbox | Seatbelt (macOS) / systemd-run (Linux) | No (kernel-enforced) |
| Credential isolation | Temp credentials via env vars | No (set before exec) |
| Service-side limits | IAM Role / Fine-grained PAT | No (server-side) |

See [docs/README.md](docs/README.md) for details.

## License

MIT
