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
for _p in \
  "$HOME/.claude" \
  "$HOME/.codex" \
  "$HOME/.kiro" \
  "$HOME/.gemini" \
  "$HOME/.local/share" \
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

# Lockfile paths: proper-lockfile creates <target>.lock next to the target.
# Claude Code uses lock directories for multiple auth-related files, including
# ~/.claude and ~/.claude.json. These paths must be writable even before the
# lock directory exists.
_SANDBOX_ALLOW_WRITE_LOCK_PATHS=""
for _p in \
  "$HOME/.claude.lock" \
  "$HOME/.claude.json.lock"
do
  _SANDBOX_ALLOW_WRITE_LOCK_PATHS="$_SANDBOX_ALLOW_WRITE_LOCK_PATHS
$_p"
done

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

_start_proxy() {
  # Read proxy config from TOML (already eval'd into shell vars)
  if [ "${PROXY_ENABLED:-false}" != "true" ] && [ "${PROXY_ENABLED:-false}" != "1" ]; then
    return
  fi
  if [ -z "${PROXY_ALLOW_DOMAINS:-}" ]; then
    echo "[$_WRAPPER_NAME] WARN: proxy enabled but no proxy_allow_domains configured, skipping" >&2
    return
  fi

  # Convert space-separated to comma-separated for proxy.py
  _domains=$(printf '%s' "$PROXY_ALLOW_DOMAINS" | tr ' ' ',')

  # Start proxy, capture port from first stdout line via FIFO
  _fifo="$_tmpdir/proxy-port"
  mkfifo "$_fifo"
  python3 "$JAILRUN_LIB/proxy.py" --allow-domains "$_domains" > "$_fifo" &
  _proxy_pid=$!
  read -r _proxy_port < "$_fifo"
  rm -f "$_fifo"

  if [ -z "$_proxy_port" ] || ! kill -0 "$_proxy_pid" 2>/dev/null; then
    echo "[$_WRAPPER_NAME] ERROR: failed to start proxy" >&2
    return
  fi

  echo "[$_WRAPPER_NAME] proxy: 127.0.0.1:$_proxy_port (pid $_proxy_pid)" >&2
  _PROXY_PORT="$_proxy_port"
  _PROXY_PID="$_proxy_pid"
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
  _start_proxy

  _build_exec_script

  # Append proxy env exports to exec.sh (before the exec line)
  if [ -n "$_PROXY_PORT" ]; then
    _proxy_script="$_tmpdir/exec-proxy.sh"
    {
      echo '#!/bin/sh'
      printf 'export HTTPS_PROXY="http://127.0.0.1:%s"\n' "$_PROXY_PORT"
      printf 'export HTTP_PROXY="http://127.0.0.1:%s"\n' "$_PROXY_PORT"
      printf 'exec "%s" "$@"\n' "$_tmpdir/exec.sh"
    } > "$_proxy_script"
    chmod +x "$_proxy_script"
  fi

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
    if [ -n "$_PROXY_PID" ]; then
      "$_tmpdir/exec-proxy.sh" "$@"
    else
      "$_tmpdir/exec.sh" "$@"
    fi
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
    _cleanup_sandbox
    rm -rf "$_tmpdir"
    exit "$_exit_code"
  else
    exec "$_tmpdir/exec.sh" "$@"
  fi
}
