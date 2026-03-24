#!/bin/sh
# sandbox construction and exec
# sourced by credential-guard.sh
#
# requires: $_tmpdir, $_WRAPPER_NAME, $_aws_config, $_aws_creds,
#           $_gh_token, $JAILRUN_LIB, $SANDBOX_EXTRA_*, $CONFIG_DIR
# exports: credential_guard_sandbox_exec()

# --- sandbox path lists (newline-separated) ---
_SANDBOX_DENY_READ_PATHS="$HOME/.aws
$HOME/.config/gh
$HOME/.gnupg
$HOME/.ssh"
for _p in $SANDBOX_EXTRA_DENY_READ; do
  case "$_p" in
    "~"*) _p="$HOME${_p#"~"}" ;;
  esac
  _SANDBOX_DENY_READ_PATHS="$_SANDBOX_DENY_READ_PATHS
$_p"
done

_SANDBOX_ALLOW_WRITE_PATHS="$HOME/.claude
$HOME/.codex
$HOME/.kiro
$HOME/.gemini
$HOME/.local/share
$HOME/.local/state
$HOME/.cache
$HOME/.npm
$HOME/.config/claude
$HOME/.config/codex
$HOME/.config/kiro"
for _p in $SANDBOX_EXTRA_ALLOW_WRITE; do
  case "$_p" in
    "~"*) _p="$HOME${_p#"~"}" ;;
  esac
  _SANDBOX_ALLOW_WRITE_PATHS="$_SANDBOX_ALLOW_WRITE_PATHS
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

_sandbox_cmd=""

case "$(uname)" in
  Darwin) . "$JAILRUN_LIB/platform/sandbox-darwin.sh" ;;
  Linux)  . "$JAILRUN_LIB/platform/sandbox-linux.sh" ;;
esac

# --- exec helpers ---

_build_git_askpass() {
  printf '#!/bin/sh\necho "$GH_TOKEN"\n' > "$_tmpdir/git-askpass"
  chmod +x "$_tmpdir/git-askpass"
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

# generate systemd EnvironmentFile from env-spec
_build_systemd_envfile() {
  local _envfile="$_tmpdir/env-systemd"
  while IFS= read -r _line; do
    case "$_line" in
      SET\ *) printf '%s\n' "${_line#SET }" ;;
    esac
  done < "$_tmpdir/env-spec" > "$_envfile"
}

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
    case "$_sandbox_cmd" in
      systemd-run)
        # Linux: pass env via EnvironmentFile (not -E argv)
        _build_systemd_envfile
        # no exec: keep exec.sh alive to maintain OSC terminal title
        # (systemd-run --pty allocates a new PTY that resets WezTerm's title tracking)
        printf 'systemd-run \\\n'
        printf '  --user --pty --wait --collect --same-dir \\\n'
        printf '  -p "EnvironmentFile=%s/env-systemd" \\\n' "$_tmpdir"
        while IFS= read -r _line; do
          case "$_line" in
            -p\ *) printf '  -p "%s" \\\n' "${_line#-p }" ;;
            *)     printf '  %s \\\n' "$_line" ;;
          esac
        done < "$_tmpdir/systemd-props"
        echo '  -- "$@"'
        ;;
      *)
        # Darwin / no sandbox
        printf 'exec %s "$@"\n' "$_sandbox_cmd"
        ;;
    esac
  } > "$_script"
  chmod +x "$_script"
}

credential_guard_sandbox_exec() {
  if [ -z "${_CREDENTIAL_GUARD_SANDBOXED:-}" ]; then
    _setup_sandbox
  fi
  _build_exec_script
  [ "${AGENT_SANDBOX_DEBUG:-}" = "1" ] && echo "[$_WRAPPER_NAME] exec: $_sandbox_cmd $*" >&2
  exec "$_tmpdir/exec.sh" "$@"
}
