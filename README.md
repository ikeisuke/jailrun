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
| `keychain_profile` | string | `"allow"` | macOS Keychain access: `"allow"` / `"deny"` / `"read-cache-only"` |
| `sandbox_extra_deny_read` | list | `[]` | Additional read-deny paths (23 paths blocked by default) |
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

#### WSL2 PTY allocation trade-off (v0.4.2+)

WSL2 上で AI コーディングエージェント TUI の直接シェル実行系（`!ls` のような
bash mode / `!` プレフィックス）を起動すると、`Application Error: Failed to
open PTY` でプロセスが死ぬ問題がありました。原因は systemd-run の
`PrivateDevices=yes` が WSL2 で devpts を正しくマウントせず、子プロセスの
PTY 確保が失敗していたことです。

v0.4.2 以降、jailrun は WSL2 を `uname -r` から検出した場合にのみ
`PrivateDevices=yes` を省略し、AppArmor プロファイルに PTY device rule
（`/dev/ptmx` + `/dev/pts/` + `owner /dev/pts/**`、最後のみ caller が所有する
PTY デバイス限定の `owner` 修飾子）を追加します。これにより WSL2 上でも
TUI の直接シェル実行が動作するようになります。

トレードオフとして、WSL2 では device isolation の強度が native Linux より
わずかに弱まります（最小 `/dev` 構築を省略）が、AppArmor 側で broad な
device 許可は行わず PTY 3 行のみに最小化しているため、攻撃面の拡大は限定的
です。native Linux と macOS（Seatbelt）の sandbox 強度・挙動は完全に従来通り
です。

詳細な発生条件と修正内容は Issue
[#90](https://github.com/ikeisuke/jailrun/issues/90) を参照してください。

#### WSL2 AppArmor primary profile setup

The AppArmor-primary sandbox path requires `securityfs` to be mounted at
`/sys/kernel/security`. WSL2 does not mount it automatically.

Mount it manually (one-time per session):

```bash
sudo mount -t securityfs securityfs /sys/kernel/security
```

To persist across reboots, add an entry to `/etc/fstab`:

```
securityfs  /sys/kernel/security  securityfs  defaults  0  0
```

Out of scope: jailrun does not provide a built-in helper for mounting
`securityfs` without root, nor an automatic mount at startup. If you want
this to be transparent, handle it in your dotfiles or systemd user units.

#### AppArmor credential deny coverage (v0.3.7+)

Under the AppArmor primary path on Linux/WSL2, credential candidate files
(e.g. `.env`, `.aws/credentials`) are denied for **read, write/create/append,
lock and symlink** operations (AppArmor mode flags `r` / `w` / `k` / `l`).
This blocks both reading existing credentials and creating or overwriting
them from inside the sandbox. Non-credential files (e.g. `notes.txt`) keep
working normally.

#### WSL2 network restriction (proxy + network namespace)

On WSL2, systemd's `IPAddressDeny`/`IPAddressAllow` properties are silently
ignored because cgroup BPF-based IP filtering does not work under the WSL2
systemd integration. The proxy starts and `HTTPS_PROXY` is set, but the
agent can bypass it by connecting directly.

To enforce network restriction on WSL2, use a **network namespace** so the
agent can only reach the proxy on a **defined TCP port range**:

```bash
# One-time setup (requires sudo, idempotent)
sudo scripts/wsl2-netns-setup.sh
```

This is kernel-enforced and cannot be bypassed from inside the namespace.

When the `agentns` namespace exists, jailrun automatically detects it and:
- Binds the proxy to `10.200.0.1` on a port inside the SoT range defined in
  `lib/netns-const.sh` (`JAILRUN_PROXY_PORT_RANGE_START..END`, currently
  `60000..60099`) instead of `127.0.0.1` on an arbitrary OS-assigned port
  (the proxy is invoked with `--enforce-port-range` only in this mode; plain
  `127.0.0.1` launches keep using the OS ephemeral pool, see PR #89)
- Launches the agent inside the namespace via `NetworkNamespacePath`

So after running the setup script, a normal `jailrun claude` will use the
namespace automatically. No sudo is required at runtime.

Since cycle v0.4.1, the namespace OUTPUT `iptables` rule is restricted to
**TCP destination ports inside that range only** (defense-in-depth): the
agent can no longer reach arbitrary services that happen to listen on
`10.200.0.1` (for example a host-side SSH daemon or local dev server).

**Verify the current OUTPUT rule** (must show a `dpts:60000:60099` range
matching the SoT):

```bash
sudo ip netns exec agentns iptables -L OUTPUT -v -n | grep dpts
# expected: ... dpts:60000:60099 ... ACCEPT
```

If the line is missing (no `dpts:` segment), you are still on the v0.4.0
setup that allowed every host IP port. Re-run the setup to upgrade:

```bash
# Re-setup for users who installed under v0.4.0 or earlier
sudo scripts/wsl2-netns-teardown.sh
sudo scripts/wsl2-netns-setup.sh
sudo ip netns exec agentns iptables -L OUTPUT -v -n | grep dpts   # confirm
```

jailrun does **not** auto-migrate the namespace at runtime (this would
require sudo every launch); the manual re-setup above is the only path.

#### WSL2 netns topology validation (v0.4.3+)

v0.4.3 以降、`scripts/wsl2-netns-setup.sh` は既存の `veth-host` を検出した
場合にトポロジー検証 3 段を実施します:

1. **peer の root NS 不在**: `veth-agent` が root namespace 側に残っていないか
2. **namespace 所属**: `veth-agent` が `agentns` namespace 内に正しく存在するか
3. **IP 厳密一致**: `veth-host` に SoT が定める `10.200.0.1/24` が割り当たっているか

部分失敗（例: 過去の setup が中断して `veth` だけ残っている / IP が剥がれている）
を検出した場合は、自動修復を試みず以下のメッセージを stderr に出力して
`exit 1` で安全停止します:

```text
[veth] inconsistent state detected: <reason>. Run 'sudo scripts/wsl2-netns-teardown.sh' and re-run setup.
```

復旧手順:

```bash
sudo scripts/wsl2-netns-teardown.sh
sudo scripts/wsl2-netns-setup.sh
```

正常パス（`veth` が存在せず新規作成 / 検証が全段成功する既存利用）では従来通り
冪等な skip / 作成挙動を維持します。詳細な検出ロジックと不整合 3 パターンの
bats テストは Issue [#87](https://github.com/ikeisuke/jailrun/issues/87) を
参照してください。

#### SoT change follow-up contract

If you ever change `JAILRUN_PROXY_PORT_RANGE_*` in `lib/netns-const.sh`,
the existing namespace's `iptables` rule keeps the **old** range until you
re-run the setup script — `sudo scripts/wsl2-netns-teardown.sh` followed
by `sudo scripts/wsl2-netns-setup.sh`. The proxy (which reads the SoT at
launch) will pick up the new range immediately, so without re-setup the
proxy's bind range and the kernel's accept range diverge: the proxy
process itself **does** start and bind successfully on the host side, but
traffic from inside `agentns` to the proxy's new port is dropped by the
old OUTPUT rule, so every CONNECT request times out. That is, the proxy
stays unreachable from the sandbox until you re-setup — not a startup
failure, a reachability failure at runtime.

To remove the namespace, run the teardown script (also idempotent — safe
to run when nothing exists or after a partially failed setup):

```bash
sudo scripts/wsl2-netns-teardown.sh
```

Out of scope: jailrun does not manage the namespace lifecycle automatically
(it does not run setup or teardown for you). Wire `scripts/wsl2-netns-setup.sh`
and `scripts/wsl2-netns-teardown.sh` into your dotfiles or systemd units as
needed.

#### Built-in proxy allow domains

When the proxy is enabled, jailrun merges three lists into the agent's
`proxy_allow_domains` and de-duplicates the result:

1. `BUILTIN_PROXY_DOMAINS_COMMON` (`lib/config.py`) — endpoints every agent
   needs (currently the GitHub family: `github.com`, `api.github.com`,
   `raw.githubusercontent.com`).
2. `BUILTIN_PROXY_DOMAINS[<agent>]` (`lib/config.py`) — agent-specific API
   and authentication endpoints. Defined for `claude`, `codex`, `kiro-cli`
   and `gemini`.
3. Your own `proxy_allow_domains` from `~/.config/jailrun/config.toml`
   (or `$XDG_CONFIG_HOME/jailrun/config.toml` when `XDG_CONFIG_HOME` is set).

So you can extend the allowlist without editing `lib/config.py` — just add
domains to your config file. Built-ins remain in effect; when a built-in
domain is already present in your `proxy_allow_domains`, the merger skips
re-adding it (so the resulting list contains each built-in domain at most
once, even if you also listed it). Duplicates inside your own
`proxy_allow_domains` are not deduplicated by the merger — keep your config
list clean if that matters to you.

The `gemini` entries shipped today are a provisional minimum (auth + Gemini
API categories). Verify against your actual `gemini` CLI traffic by enabling
the proxy and inspecting `$_tmpdir/proxy.log` (announced on stderr at
proxy start), then file an issue if domains are missing.

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
