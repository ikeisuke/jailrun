#!/bin/sh
# sandbox construction and exec
# sourced by credential-guard.sh
#
# requires: $_tmpdir, $_WRAPPER_NAME, $_aws_config, $_aws_creds,
#           $_gh_token, $JAILRUN_LIB, $SANDBOX_EXTRA_*, $CONFIG_DIR
# exports: credential_guard_sandbox_exec()

# ============================================================
# Section 1: Sandbox path lists (newline-separated)
# ============================================================

# Contract: _SANDBOX_ALLOW_WRITE_PATHS contains only existing directories.
# Platform backends may rely on this guarantee (e.g. systemd ReadWritePaths).
_SANDBOX_DENY_READ_PATHS="$HOME/.aws
$HOME/.config/gh
$HOME/.gnupg
$HOME/.ssh
$HOME/.config/gcloud
$HOME/.azure
$HOME/.oci
$HOME/.docker
$HOME/.kube
$HOME/.wrangler
$HOME/.config/wrangler
$HOME/.fly
$HOME/.config/netlify
$HOME/.config/vercel
$HOME/.config/heroku
$HOME/.terraform.d
$HOME/.vault-token
$HOME/.config/op
$HOME/.config/hub
$HOME/.config/stripe
$HOME/.config/firebase
$HOME/.netrc
$HOME/.npmrc"
for _p in $SANDBOX_EXTRA_DENY_READ; do
  case "$_p" in
    "~"*) _p="$HOME${_p#"~"}" ;;
  esac
  _SANDBOX_DENY_READ_PATHS="$_SANDBOX_DENY_READ_PATHS
$_p"
done

_SANDBOX_ALLOW_WRITE_PATHS=""
# Cross-platform paths: create if missing (safe to mkdir)
# Note: ~/.kiro, ~/.local/share, ~/.codex are intentionally NOT listed here;
# they are moved to _SANDBOX_ALLOW_WRITE_LOCK_PATHS below because they use
# SQLite WAL which requires the lock (k) AppArmor permission (Issue #78).
for _p in \
  "$HOME/.claude" \
  "$HOME/.gemini" \
  "$HOME/.local/state" \
  "$HOME/.cache" \
  "$HOME/.npm" \
  "$HOME/.config/claude" \
  "$HOME/.config/codex" \
  "$HOME/.config/kiro"
do
  [ -d "$_p" ] || mkdir -p "$_p" 2>/dev/null || continue
  _SANDBOX_ALLOW_WRITE_PATHS="$_SANDBOX_ALLOW_WRITE_PATHS
$_p"
done
# Platform-specific paths: add only if they already exist
for _p in \
  "$HOME/Library/Application Support/Claude" \
  "$HOME/Library/Application Support/Codex" \
  "$HOME/Library/Application Support/kiro-cli"
do
  [ -d "$_p" ] || continue
  _SANDBOX_ALLOW_WRITE_PATHS="$_SANDBOX_ALLOW_WRITE_PATHS
$_p"
done
# Keychain write access: controlled by keychain_profile config setting.
# SecurityServer (securityd) requires file-level writes to Keychain DBs for
# in-sandbox auth token refresh. file-read deny has no effect on Keychain reads
# because SecurityServer reads Keychain DBs in its own process context.
# See: .aidlc/cycles/v0.2.1/design-artifacts/keychain-investigation-report.md
case "${KEYCHAIN_PROFILE:-allow}" in
  allow)
    if [ -d "$HOME/Library/Keychains" ]; then
      _SANDBOX_ALLOW_WRITE_PATHS="$_SANDBOX_ALLOW_WRITE_PATHS
$HOME/Library/Keychains"
    fi
    ;;
  deny|read-cache-only)
    # ~/Library/Keychains not added — Keychain writes blocked by Seatbelt.
    # Users must authenticate outside the sandbox first.
    ;;
esac
for _p in $SANDBOX_EXTRA_ALLOW_WRITE; do
  case "$_p" in
    "~"*) _p="$HOME${_p#"~"}" ;;
  esac
  [ -d "$_p" ] || mkdir -p "$_p" 2>/dev/null || continue
  _SANDBOX_ALLOW_WRITE_PATHS="$_SANDBOX_ALLOW_WRITE_PATHS
$_p"
done

# Lock-required directories: backends emit rwk (read+write+lock) AppArmor rules
# for these paths. The list mixes two pre-creation policies — decided per-entry
# by the caller (see Issue #23 for the proper-lockfile rationale):
#
#   1. proper-lockfile `.lock` virtual directories (e.g. ~/.claude.lock,
#      ~/.claude.json.lock): DO NOT pre-create. proper-lockfile uses mkdir
#      to acquire the lock; a pre-created directory would look permanently
#      held. Backends must tolerate the path being absent.
#   2. Real directories that must exist for the CLI to function (e.g.
#      ~/.kiro, ~/.local/share for kiro-cli SQLite/JSON file_lock):
#      pre-create with mkdir -p is SAFE and recommended (Issue #78).
#
# systemd backend filters with `[ -d "$_p" ] || continue` (sandbox-linux-systemd.sh).
# AppArmor backend emits rules unconditionally (non-existent paths are valid).
_SANDBOX_ALLOW_WRITE_LOCK_PATHS=""

# Policy 1: proper-lockfile lock paths (no pre-create)
for _p in \
  "$HOME/.claude.lock" \
  "$HOME/.claude.json.lock"
do
  _SANDBOX_ALLOW_WRITE_LOCK_PATHS="$_SANDBOX_ALLOW_WRITE_LOCK_PATHS
$_p"
done

# Policy 2: kiro-cli specific lock-required real directories.
# kiro-cli uses SQLite/JSON file_lock inside these directories; the lock (k)
# permission is required in AppArmor (Issue #78).
# Future abstraction candidate: SANDBOX_EXTRA_LOCK_PATHS env var (recorded in
# Construction Phase decisions.md).
for _p in \
  "$HOME/.codex" \
  "$HOME/.kiro" \
  "$HOME/.local/share"
do
  [ -d "$_p" ] || mkdir -p "$_p" 2>/dev/null || continue
  _SANDBOX_ALLOW_WRITE_LOCK_PATHS="$_SANDBOX_ALLOW_WRITE_LOCK_PATHS
$_p"
done

# Optional: kiro-cli log directory (only added when XDG_RUNTIME_DIR is set
# by the user environment; falls back to no-op otherwise).
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  _p="$XDG_RUNTIME_DIR/kiro-log"
  [ -d "$_p" ] || mkdir -p "$_p" 2>/dev/null
  if [ -d "$_p" ]; then
    _SANDBOX_ALLOW_WRITE_LOCK_PATHS="$_SANDBOX_ALLOW_WRITE_LOCK_PATHS
$_p"
  fi
fi

_SANDBOX_ALLOW_WRITE_FILES="$HOME/.claude.json"
for _p in $SANDBOX_EXTRA_ALLOW_WRITE_FILES; do
  case "$_p" in
    "~"*) _p="$HOME${_p#"~"}" ;;
  esac
  _SANDBOX_ALLOW_WRITE_FILES="$_SANDBOX_ALLOW_WRITE_FILES
$_p"
done

_regex_escape() {
  printf '%s' "$1" | sed 's/[][(){}.^$+*?|\\]/\\&/g'
}

_home_regex=$(_regex_escape "$HOME")
_SANDBOX_ALLOW_WRITE_REGEXES="^${_home_regex}/\\.claude\\.json\\.tmp\\.[^/]+$"

# Build deny-read regexes from filename list (e.g. ".env" -> /\.env$)
_SANDBOX_DENY_READ_REGEXES=""
for _name in $SANDBOX_DENY_READ_NAMES; do
  _escaped=$(_regex_escape "$_name")
  _SANDBOX_DENY_READ_REGEXES="$_SANDBOX_DENY_READ_REGEXES
/$_escaped\$"
done

# ============================================================
# Section 2: Platform backend loading
# ============================================================

_sandbox_cmd=""

case "$(uname)" in
  Darwin) . "$JAILRUN_LIB/platform/sandbox-darwin.sh" ;;
  Linux)  . "$JAILRUN_LIB/platform/sandbox-linux.sh" ;;
esac

# ============================================================
# Section 3: Environment spec generation (env-spec)
# ============================================================

_build_git_askpass() {
  printf '#!/bin/sh\necho "$GH_TOKEN"\n' > "$_tmpdir/git-askpass"
  chmod 0700 "$_tmpdir/git-askpass"
}

# generate env var spec file (SET/UNSET format)
_build_env_spec() {
  local _spec="$_tmpdir/env-spec"
  {
    echo 'UNSET AWS_ACCESS_KEY_ID'
    echo 'UNSET AWS_SECRET_ACCESS_KEY'
    echo 'UNSET AWS_SESSION_TOKEN'
    echo 'UNSET AWS_PROFILE'
    echo 'UNSET AWS_DEFAULT_PROFILE'
    echo 'UNSET AWS_ROLE_ARN'
    echo 'UNSET AWS_ROLE_SESSION_NAME'
    echo 'UNSET GH_TOKEN'
    echo 'UNSET GITHUB_TOKEN'
    # Fallback: clear D-Bus address for abstract sockets (can't use InaccessiblePaths)
    # Use SET (empty) not UNSET — systemd-run --user needs the address to start
    if [ "${_DBUS_NEEDS_ENV_CLEAR:-}" = "1" ]; then
      echo 'SET DBUS_SESSION_BUS_ADDRESS='
    fi
    _systemd_user=$(id -un 2>/dev/null || printf '%s' "${USER:-}")
    printf 'SET HOME=%s\n' "$HOME"
    if [ -n "$_systemd_user" ]; then
      printf 'SET USER=%s\n' "$_systemd_user"
      printf 'SET LOGNAME=%s\n' "$_systemd_user"
    fi
    printf 'SET SHELL=%s\n' "${SHELL:-/bin/sh}"
    if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
      printf 'SET XDG_RUNTIME_DIR=%s\n' "$XDG_RUNTIME_DIR"
    fi
    if [ -n "${TERM:-}" ]; then
      printf 'SET TERM=%s\n' "$TERM"
    fi
    printf 'SET AWS_CONFIG_FILE=%s\n' "$_aws_config"
    printf 'SET AWS_SHARED_CREDENTIALS_FILE=%s\n' "$_aws_creds"
    printf 'SET GH_CONFIG_DIR=%s/gh\n' "$_tmpdir"
    echo 'SET SSH_AUTH_SOCK='
    # Provide CA certs via file for environments where native cert store is unavailable
    if [ -f /etc/ssl/cert.pem ]; then
      echo 'SET SSL_CERT_FILE=/etc/ssl/cert.pem'
    fi
    printf 'SET PATH=%s/shims:%s\n' "$JAILRUN_LIB" "$PATH"
    if [ -n "$_gh_token" ]; then
      _build_git_askpass
      printf 'SET GH_TOKEN=%s\n' "$_gh_token"
      printf 'SET GIT_ASKPASS=%s/git-askpass\n' "$_tmpdir"
      echo 'SET GIT_TERMINAL_PROMPT=0'
      echo 'SET GIT_CONFIG_COUNT=2'
      echo 'SET GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf'
      echo 'SET GIT_CONFIG_VALUE_0=git@github.com:'
      echo 'SET GIT_CONFIG_KEY_1=url.https://github.com/.insteadOf'
      echo 'SET GIT_CONFIG_VALUE_1=ssh://git@github.com/'
    fi
    if [ -z "${_CREDENTIAL_GUARD_SANDBOXED:-}" ] && [ -n "$_sandbox_cmd" ]; then
      echo 'SET _CREDENTIAL_GUARD_SANDBOXED=1'
    fi
    if [ -n "${_PROXY_PORT:-}" ]; then
      _proxy_url="http://${_PROXY_BIND:-127.0.0.1}:$_PROXY_PORT"
      printf 'SET HTTPS_PROXY=%s\n' "$_proxy_url"
      printf 'SET HTTP_PROXY=%s\n' "$_proxy_url"
      printf 'SET https_proxy=%s\n' "$_proxy_url"
      printf 'SET http_proxy=%s\n' "$_proxy_url"
      # Node.js 24+ native fetch respects proxy env vars only with this flag
      echo 'SET NODE_USE_ENV_PROXY=1'
    fi
    # Passthrough custom environment variables
    # Values are escaped for safe embedding in double-quoted shell context
    for _var in $SANDBOX_PASSTHROUGH_ENV; do
      # Block reserved credential variables that the sandbox explicitly manages
      case "$_var" in
        AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN|\
        AWS_PROFILE|AWS_DEFAULT_PROFILE|AWS_ROLE_ARN|AWS_ROLE_SESSION_NAME|\
        AWS_CONFIG_FILE|AWS_SHARED_CREDENTIALS_FILE|\
        GH_TOKEN|GITHUB_TOKEN|GH_CONFIG_DIR|\
        SSH_AUTH_SOCK|DBUS_SESSION_BUS_ADDRESS|\
        PATH|GIT_ASKPASS|GIT_TERMINAL_PROMPT|\
        GIT_CONFIG_COUNT|GIT_CONFIG_KEY_*|GIT_CONFIG_VALUE_*|\
        _CREDENTIAL_GUARD_SANDBOXED)
          echo "[$_WRAPPER_NAME] WARN: ignoring reserved variable in SANDBOX_PASSTHROUGH_ENV: $_var" >&2
          continue ;;
      esac
      # Validate variable name is a valid shell identifier
      case "$_var" in
        [!A-Za-z_]*|*[!A-Za-z0-9_]*)
          echo "[$_WRAPPER_NAME] WARN: skipping invalid variable name: $_var" >&2
          continue ;;
      esac
      eval "_val=\"\${$_var:-}\""
      if [ -n "$_val" ]; then
        # Reject values containing newlines (env-spec is line-based)
        case "$_val" in
          *"
"*) echo "[$_WRAPPER_NAME] WARN: skipping $_var (value contains newlines)" >&2
              continue ;;
        esac
        _escaped=$(printf '%s' "$_val" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\$/\\$/g; s/`/\\`/g')
        printf 'SET %s=%s\n' "$_var" "$_escaped"
      fi
    done
  } > "$_spec"
}

# ============================================================
# Section 4: Exec script generation
# ============================================================

# generate exec.sh: env setup + sandbox command + exec
_build_exec_script() {
  local _script="$_tmpdir/exec.sh"
  _build_env_spec

  {
    echo '#!/bin/sh'
    # set terminal title to agent name (avoids WezTerm showing full sandbox command)
    printf 'printf '\''\\033]0;jailrun %%s\\007'\'' "${1##*/}"\n'
    # emit unset/export from env-spec (hides secrets from ps argv)
    while IFS= read -r _line; do
      case "$_line" in
        UNSET\ *) printf 'unset %s\n' "${_line#UNSET }" ;;
        SET\ *)
          _envpair="${_line#SET }"
          _envkey="${_envpair%%=*}"
          _envval="${_envpair#*=}"
          printf 'export %s="%s"\n' "$_envkey" "$_envval"
          ;;
      esac
    done < "$_tmpdir/env-spec"
    # Append platform-specific sandbox exec (provided by backend)
    if type _build_sandbox_exec >/dev/null 2>&1; then
      _build_sandbox_exec
    else
      printf 'exec "$@"\n'
    fi
  } > "$_script"
  chmod +x "$_script"
}

# ============================================================
# Section 5: Proxy management
# ============================================================

# Load network namespace topology constants (single source of truth)
if [ ! -f "$JAILRUN_LIB/netns-const.sh" ]; then
  echo "[$_WRAPPER_NAME] error: netns constants not found: \$JAILRUN_LIB/netns-const.sh" >&2
  exit 1
fi
. "$JAILRUN_LIB/netns-const.sh"
if [ -z "${JAILRUN_NETNS_NAME:-}" ] || [ -z "${JAILRUN_NETNS_HOST_IP:-}" ]; then
  echo "[$_WRAPPER_NAME] error: netns constants incomplete in \$JAILRUN_LIB/netns-const.sh" >&2
  exit 1
fi

# Detect network namespace early (before _setup_sandbox generates systemd-props)
_NETNS=""
if ip netns list 2>/dev/null | grep -qw "$JAILRUN_NETNS_NAME"; then
  _NETNS="$JAILRUN_NETNS_NAME"
fi

# Fail-fast guard: NetworkNamespacePath requires systemd >= 243.
# Older systemd silently drops the property and the agent would run in the
# host namespace while the proxy is bound to 10.200.0.1 — a fail-open of the
# network restriction. Refuse to start instead of pretending to be isolated.
if [ -n "$_NETNS" ] && command -v systemd-run >/dev/null 2>&1; then
  _sd_ver=$(systemd-run --version 2>/dev/null | awk 'NR==1 {print $2}')
  case "$_sd_ver" in
    ''|*[!0-9]*) : ;;
    *)
      if [ "$_sd_ver" -lt 243 ]; then
        echo "[$_WRAPPER_NAME] error: agentns requires systemd >= 243 for NetworkNamespacePath (current: $_sd_ver)" >&2
        echo "[$_WRAPPER_NAME] error: older systemd silently ignores it, which would fail-open the network restriction" >&2
        exit 1
      fi
      ;;
  esac
fi

# Verify that systemd-run actually joins the detected network namespace.
# Some systemd/user-manager combinations accept NetworkNamespacePath but log
# "network namespace setup failed, ignoring" and continue in the host netns.
# That is fail-open for jailrun's WSL2 network restriction, so compare the
# namespace device:inode from inside a transient unit against /run/netns/$name.
_SYSTEMD_RUN_MODE="user"
_SYSTEMD_RUN_USER=""
_SYSTEMD_RUN_GROUP=""

_run_netns_join_check() {
  local _mode="$1"
  local _actual_file="$2"
  local _run_log="$3"
  rm -f "$_actual_file" "$_run_log"

  case "$_mode" in
    user)
      systemd-run --user --wait --collect --quiet \
        -p "NetworkNamespacePath=/run/netns/$_NETNS" \
        -- sh -c 'stat -Lc "%d:%i" /proc/self/ns/net > "$1"' _ "$_actual_file" \
        >"$_run_log" 2>&1
      ;;
    root)
      sudo -n systemd-run --wait --collect --quiet \
        -p "User=$_SYSTEMD_RUN_USER" \
        -p "Group=$_SYSTEMD_RUN_GROUP" \
        -p "NetworkNamespacePath=/run/netns/$_NETNS" \
        -- sh -c 'stat -Lc "%d:%i" /proc/self/ns/net > "$1"' _ "$_actual_file" \
        >"$_run_log" 2>&1
      ;;
  esac
}

_verify_netns_join_support() {
  [ -n "${_NETNS:-}" ] || return 0

  local _expected_ns _user_actual_file _user_log _root_actual_file _root_log
  local _user_actual_ns _root_actual_ns
  _expected_ns=$(stat -Lc '%d:%i' "/run/netns/$_NETNS" 2>/dev/null) || {
    echo "[$_WRAPPER_NAME] error: cannot inspect network namespace '/run/netns/$_NETNS'" >&2
    echo "[$_WRAPPER_NAME] hint: run 'sudo scripts/wsl2-netns-setup.sh' to recreate the namespace, or remove agentns to disable netns" >&2
    return 1
  }

  _SYSTEMD_RUN_USER=$(id -un 2>/dev/null || printf '%s' "${USER:-}")
  _SYSTEMD_RUN_GROUP=$(id -gn 2>/dev/null || printf '%s' "${GROUP:-}")
  if [ -z "$_SYSTEMD_RUN_USER" ] || [ -z "$_SYSTEMD_RUN_GROUP" ]; then
    echo "[$_WRAPPER_NAME] error: cannot determine current user/group for netns systemd-run" >&2
    return 1
  fi

  _user_actual_file="$_tmpdir/netns-check.user.actual"
  _user_log="$_tmpdir/netns-check.user.log"
  if _run_netns_join_check user "$_user_actual_file" "$_user_log"; then
    _user_actual_ns=$(sed -n '1p' "$_user_actual_file" 2>/dev/null)
    if [ "$_user_actual_ns" = "$_expected_ns" ]; then
      _SYSTEMD_RUN_MODE="user"
      return 0
    fi
  fi

  _root_actual_file="$_tmpdir/netns-check.root.actual"
  _root_log="$_tmpdir/netns-check.root.log"
  if command -v sudo >/dev/null 2>&1 && _run_netns_join_check root "$_root_actual_file" "$_root_log"; then
    _root_actual_ns=$(sed -n '1p' "$_root_actual_file" 2>/dev/null)
    if [ "$_root_actual_ns" = "$_expected_ns" ]; then
      _SYSTEMD_RUN_MODE="root"
      echo "[$_WRAPPER_NAME] WARN: systemd-run --user did not enter '$_NETNS'; using sudo -n systemd-run with User=$_SYSTEMD_RUN_USER" >&2
      return 0
    fi
  fi

  echo "[$_WRAPPER_NAME] error: cannot start inside network namespace '$_NETNS'" >&2
  echo "[$_WRAPPER_NAME] error: expected $_expected_ns; user systemd-run got ${_user_actual_ns:-<empty>}; sudo systemd-run got ${_root_actual_ns:-<empty>}" >&2
  if [ -s "$_user_log" ]; then
    sed "s/^/[$_WRAPPER_NAME] systemd-run --user: /" "$_user_log" >&2
  fi
  if [ -s "$_root_log" ]; then
    sed "s/^/[$_WRAPPER_NAME] sudo systemd-run: /" "$_root_log" >&2
  fi
  echo "[$_WRAPPER_NAME] hint: run 'sudo -v' and retry, or remove agentns to disable netns" >&2
  return 1
}

# Single decision point: should _start_proxy actually launch the proxy?
# Both the readiness gate below and _start_proxy consult this so the
# "is the proxy going to bind?" question has one answer per invocation.
_proxy_should_start() {
  case "${PROXY_ENABLED:-false}" in
    true|1) ;;
    *) return 1 ;;
  esac
  [ -n "${PROXY_ALLOW_DOMAINS:-}" ]
}

# Verify host-side resources required for the proxy bind. Returns 1 on
# failure (with a stderr message naming the missing resource and a hint);
# the top-level launch block decides whether to exit. Keeping `exit` out
# of this function makes it unit-testable from bats without killing the
# test runner.
_verify_proxy_readiness() {
  if ! ip link show "$JAILRUN_NETNS_VETH_HOST" >/dev/null 2>&1; then
    echo "[$_WRAPPER_NAME] error: agentns detected but host veth '$JAILRUN_NETNS_VETH_HOST' is missing" >&2
    echo "[$_WRAPPER_NAME] hint: run 'sudo scripts/wsl2-netns-setup.sh' to (re)create the namespace, or remove agentns to disable netns" >&2
    return 1
  fi
  # Use fixed-string match against the exact CIDR-delimited form ("inet
  # 10.200.0.1/24") so the IP literal is not interpreted as a regex (a `.`
  # would otherwise match any character and weaken the fail-closed check).
  if ! ip -o -4 addr show dev "$JAILRUN_NETNS_VETH_HOST" 2>/dev/null \
    | grep -Fq " $JAILRUN_NETNS_HOST_IP/"; then
    echo "[$_WRAPPER_NAME] error: agentns detected but host IP '$JAILRUN_NETNS_HOST_IP' is not assigned to '$JAILRUN_NETNS_VETH_HOST'" >&2
    echo "[$_WRAPPER_NAME] hint: run 'sudo scripts/wsl2-netns-setup.sh' to (re)create the namespace, or remove agentns to disable netns" >&2
    return 1
  fi
  return 0
}

# Fail-closed: on WSL2, IPAddressDeny is silently ignored so agentns is
# the only kernel-enforced network restriction.  Refuse to start when the
# proxy expects network restriction but agentns is absent.
if _is_wsl2 && _proxy_should_start && [ -z "$_NETNS" ]; then
  echo "[$_WRAPPER_NAME] error: WSL2 network restriction requires agentns but namespace not found" >&2
  echo "[$_WRAPPER_NAME] error: IPAddressDeny is ineffective on WSL2; proxy can be bypassed without agentns" >&2
  echo "[$_WRAPPER_NAME] hint: run 'sudo scripts/wsl2-netns-setup.sh' to create the namespace" >&2
  exit 1
fi

# Verify that agentns iptables OUTPUT policy is DROP.  Without this, the
# namespace exists but traffic is not restricted (fail-open).
_verify_agentns_iptables_policy() {
  if ! sudo -n ip netns exec "$_NETNS" iptables -S OUTPUT 2>/dev/null \
    | grep -q -- '-P OUTPUT DROP'; then
    echo "[$_WRAPPER_NAME] error: agentns iptables OUTPUT policy is not DROP" >&2
    echo "[$_WRAPPER_NAME] hint: run 'sudo scripts/wsl2-netns-setup.sh' to restore iptables rules" >&2
    return 1
  fi
}

# Readiness launch blocks: when the namespace is active, first prove a
# systemd-launched unit can actually enter it (user manager, or sudo fallback).
# Then, only when the proxy will bind, verify the host-side veth resources
# and iptables policy.
# Fail-closed: no host-net fallback.
if [ -n "$_NETNS" ]; then
  _verify_netns_join_support || exit 1
fi
if [ -n "$_NETNS" ] && _proxy_should_start; then
  _verify_proxy_readiness || exit 1
  _verify_agentns_iptables_policy || exit 1
fi

_start_proxy() {
  # Read proxy config from TOML (already eval'd into shell vars).
  # Surface the "enabled but no domains" misconfiguration before consulting
  # _proxy_should_start so users still see the WARN that used to live here.
  case "${PROXY_ENABLED:-false}" in
    true|1)
      if [ -z "${PROXY_ALLOW_DOMAINS:-}" ]; then
        echo "[$_WRAPPER_NAME] WARN: proxy enabled but no proxy_allow_domains configured, skipping" >&2
      fi
      ;;
  esac
  # "proxy not enabled / no domains" is a normal skip path.
  # Return success here; otherwise caller (under set -e) aborts before agent exec.
  _proxy_should_start || return 0

  # Convert space-separated to comma-separated for proxy.py
  _domains=$(printf '%s' "$PROXY_ALLOW_DOMAINS" | tr ' ' ',')

  # Bind to veth-host IP when network namespace is active. In netns mode we
  # also pass --enforce-port-range so proxy.py constrains its bind to the
  # SoT range JAILRUN_PROXY_PORT_RANGE_START..END (lib/netns-const.sh, see
  # cycle v0.4.1 / Unit 002) — this is what keeps proxy bind and the netns
  # OUTPUT --dport rule in lock-step. Outside netns we deliberately leave
  # the flag off so plain 127.0.0.1 launches keep using the full OS
  # ephemeral pool (v0.4.0 behaviour, see PR #89 pre-merge review).
  _proxy_bind="127.0.0.1"
  _proxy_extra_args=""
  if [ -n "$_NETNS" ]; then
    _proxy_bind="$JAILRUN_NETNS_HOST_IP"
    _proxy_extra_args="--enforce-port-range"
  fi

  # Start proxy, capture port from first stdout line via FIFO.
  # Always persist proxy stderr so bind/DNS/CONNECT errors are visible
  # even without AGENT_SANDBOX_DEBUG=1; announce the path on launch so
  # users can find it whether or not the proxy starts successfully.
  _fifo="$_tmpdir/proxy-port"
  mkfifo "$_fifo"
  _proxy_log="$_tmpdir/proxy.log"
  python3 "$JAILRUN_LIB/proxy.py" --allow-domains "$_domains" --bind "$_proxy_bind" $_proxy_extra_args > "$_fifo" 2>"$_proxy_log" &
  _proxy_pid=$!
  echo "[$_WRAPPER_NAME] proxy log: $_proxy_log" >&2
  read -r _proxy_port < "$_fifo"
  rm -f "$_fifo"

  if [ -z "$_proxy_port" ] || ! kill -0 "$_proxy_pid" 2>/dev/null; then
    echo "[$_WRAPPER_NAME] ERROR: failed to start proxy" >&2
    return
  fi

  echo "[$_WRAPPER_NAME] proxy: $_proxy_bind:$_proxy_port (pid $_proxy_pid)" >&2
  _PROXY_PORT="$_proxy_port"
  _PROXY_PID="$_proxy_pid"
  _PROXY_BIND="$_proxy_bind"
  _PROXY_LOG="$_proxy_log"
}

_preserve_proxy_log_on_failure() {
  [ "${_exit_code:-0}" -ne 0 ] || return 0
  [ -n "${_PROXY_LOG:-}" ] || return 0
  [ -s "$_PROXY_LOG" ] || return 0

  _saved_proxy_log="/tmp/jailrun-${_WRAPPER_NAME}-proxy-$$.log"
  if cp "$_PROXY_LOG" "$_saved_proxy_log" 2>/dev/null; then
    chmod 0600 "$_saved_proxy_log" 2>/dev/null || true
    echo "[$_WRAPPER_NAME] proxy log saved: $_saved_proxy_log" >&2
  fi
}

# ============================================================
# Section 6: Main entry point
# ============================================================

credential_guard_sandbox_exec() {
  if [ -z "${_CREDENTIAL_GUARD_SANDBOXED:-}" ]; then
    _setup_sandbox
  fi

  # Start deny log collection only in debug mode (Darwin: log stream, Linux: no-op)
  _DENY_LOG_PID=""
  _DENY_LOG_FILE=""
  if [ "${AGENT_SANDBOX_DEBUG:-}" = "1" ]; then
    _start_deny_log
  fi

  # Start proxy if enabled
  _PROXY_PORT=""
  _PROXY_PID=""
  _PROXY_LOG=""
  _start_proxy

  _build_exec_script

  # Proxy env vars are now emitted by _build_env_spec (env-spec) so
  # exec.sh already exports HTTPS_PROXY/HTTP_PROXY/etc. No separate
  # exec-proxy.sh wrapper is needed.

  if [ -n "$_sandbox_cmd" ]; then
    echo "[$_WRAPPER_NAME] sandbox: $_sandbox_cmd" >&2
  else
    echo "[$_WRAPPER_NAME] sandbox: none" >&2
  fi
  [ "${AGENT_SANDBOX_DEBUG:-}" = "1" ] && echo "[$_WRAPPER_NAME] exec: $_sandbox_cmd $*" >&2

  if [ -n "$_PROXY_PID" ] || [ -n "$_DENY_LOG_PID" ] || [ -n "${_APPARMOR_PROFILE_LOADED:-}" ]; then
    # Proxy or deny log running — can't exec, need to wait and clean up
    # EXIT trap ensures cleanup even if shell is killed by signal.
    # Must include rm -rf to preserve credentials.sh's tmpdir cleanup.
    trap '_stop_deny_log; _cleanup_sandbox; [ -n "$_PROXY_PID" ] && kill "$_PROXY_PID" 2>/dev/null; rm -rf "$_tmpdir"' EXIT
    "$_tmpdir/exec.sh" "$@"
    _exit_code=$?
    trap - EXIT
    _stop_deny_log
    if [ -n "$_DENY_LOG_FILE" ] && [ -s "$_DENY_LOG_FILE" ]; then
      echo "[$_WRAPPER_NAME] === Seatbelt deny log ===" >&2
      cat "$_DENY_LOG_FILE" >&2
      echo "[$_WRAPPER_NAME] === end deny log ===" >&2
    fi
    if [ -n "$_PROXY_PID" ]; then
      kill "$_PROXY_PID" 2>/dev/null || true
      wait "$_PROXY_PID" 2>/dev/null || true
    fi
    _preserve_proxy_log_on_failure
    _cleanup_sandbox
    rm -rf "$_tmpdir"
    exit "$_exit_code"
  else
    exec "$_tmpdir/exec.sh" "$@"
  fi
}
