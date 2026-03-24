#!/bin/sh
# Config management command
# Usage: jailrun config <subcommand> [options]
#
# Subcommands: show, set, edit, path, init

set -eu

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/jailrun"
CONFIG_FILE="$CONFIG_DIR/config"

# known config keys (space-separated)
_KNOWN_KEYS="ALLOWED_AWS_PROFILES DEFAULT_AWS_PROFILE GH_TOKEN_NAME SANDBOX_EXTRA_DENY_READ SANDBOX_EXTRA_ALLOW_WRITE SANDBOX_EXTRA_ALLOW_WRITE_FILES SANDBOX_PASSTHROUGH_ENV"

# list-type keys (support --append / --remove)
_LIST_KEYS="ALLOWED_AWS_PROFILES SANDBOX_EXTRA_DENY_READ SANDBOX_EXTRA_ALLOW_WRITE SANDBOX_EXTRA_ALLOW_WRITE_FILES SANDBOX_PASSTHROUGH_ENV"

_is_known_key() {
  for _k in $_KNOWN_KEYS; do
    [ "$_k" = "$1" ] && return 0
  done
  return 1
}

_is_list_key() {
  for _k in $_LIST_KEYS; do
    [ "$_k" = "$1" ] && return 0
  done
  return 1
}

# --- show ---
_cmd_show() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "[config] no config file found: $CONFIG_FILE" >&2
    echo "[config] run 'jailrun config init' to create one" >&2
    exit 1
  fi

  # source defaults then config
  ALLOWED_AWS_PROFILES=""
  DEFAULT_AWS_PROFILE=""
  GH_TOKEN_NAME="classic"
  SANDBOX_EXTRA_DENY_READ=""
  SANDBOX_EXTRA_ALLOW_WRITE=""
  SANDBOX_EXTRA_ALLOW_WRITE_FILES=""
  SANDBOX_PASSTHROUGH_ENV=""
  . "$CONFIG_FILE"

  for _k in $_KNOWN_KEYS; do
    eval "_v=\"\$$_k\""
    printf '%s="%s"\n' "$_k" "$_v"
  done
}

# --- set ---
_cmd_set() {
  _mode="replace"
  # parse flags
  while [ $# -gt 0 ]; do
    case "$1" in
      --append)  _mode="append";  shift ;;
      --remove)  _mode="remove";  shift ;;
      -*) echo "[config] ERROR: unknown flag '$1'" >&2; exit 1 ;;
      *)  break ;;
    esac
  done

  if [ $# -lt 1 ]; then
    echo "[config] ERROR: missing KEY" >&2
    echo "Usage: jailrun config set [--append|--remove] KEY VALUE" >&2
    exit 1
  fi
  _key="$1"; shift

  if ! _is_known_key "$_key"; then
    echo "[config] ERROR: unknown key '$_key'" >&2
    echo "[config] known keys: $_KNOWN_KEYS" >&2
    exit 1
  fi

  if [ "$_mode" != "replace" ] && ! _is_list_key "$_key"; then
    echo "[config] ERROR: --${_mode} is only supported for list-type keys" >&2
    echo "[config] list keys: $_LIST_KEYS" >&2
    exit 1
  fi

  if [ "$_mode" = "replace" ] && [ $# -lt 1 ]; then
    echo "[config] ERROR: missing VALUE" >&2
    exit 1
  fi

  if [ ! -f "$CONFIG_FILE" ]; then
    echo "[config] no config file found: $CONFIG_FILE" >&2
    echo "[config] run 'jailrun config init' to create one" >&2
    exit 1
  fi

  _value="${1:-}"

  # warn on shell-unsafe characters
  case "$_value" in
    *\`*|*\$\(*|*\;*|*\|*|*\&*|*\>*|*\<*)
      echo "[config] WARN: value contains shell-unsafe characters" >&2
      ;;
  esac

  if [ "$_mode" = "append" ] || [ "$_mode" = "remove" ]; then
    # read current value
    ALLOWED_AWS_PROFILES=""
    DEFAULT_AWS_PROFILE=""
    GH_TOKEN_NAME="classic"
    SANDBOX_EXTRA_DENY_READ=""
    SANDBOX_EXTRA_ALLOW_WRITE=""
    SANDBOX_EXTRA_ALLOW_WRITE_FILES=""
    SANDBOX_PASSTHROUGH_ENV=""
    . "$CONFIG_FILE"
    eval "_current=\"\$$_key\""

    if [ "$_mode" = "append" ]; then
      # avoid duplicates
      _found=false
      for _w in $_current; do
        [ "$_w" = "$_value" ] && _found=true
      done
      if [ "$_found" = true ]; then
        echo "[config] '$_value' already in $_key" >&2
        return 0
      fi
      if [ -n "$_current" ]; then
        _value="$_current $_value"
      fi
    else
      # remove
      _new=""
      for _w in $_current; do
        [ "$_w" != "$_value" ] && _new="${_new:+$_new }$_w"
      done
      _value="$_new"
    fi
  fi

  # update config file: replace existing line or append
  _tmp="$CONFIG_FILE.tmp.$$"
  _replaced=false
  while IFS= read -r _line; do
    case "$_line" in
      "$_key="*|"#$_key="*)
        printf '%s="%s"\n' "$_key" "$_value"
        _replaced=true
        ;;
      *)
        printf '%s\n' "$_line"
        ;;
    esac
  done < "$CONFIG_FILE" > "$_tmp"

  if [ "$_replaced" = false ]; then
    printf '%s="%s"\n' "$_key" "$_value" >> "$_tmp"
  fi

  mv "$_tmp" "$CONFIG_FILE"
}

# --- edit ---
_cmd_edit() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "[config] no config file found: $CONFIG_FILE" >&2
    echo "[config] run 'jailrun config init' to create one" >&2
    exit 1
  fi
  exec "${EDITOR:-vi}" "$CONFIG_FILE"
}

# --- path ---
_cmd_path() {
  echo "$CONFIG_FILE"
}

# --- init ---
_cmd_init() {
  _force=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) _force=true; shift ;;
      *) echo "[config] ERROR: unknown flag '$1'" >&2; exit 1 ;;
    esac
  done

  if [ -f "$CONFIG_FILE" ] && [ "$_force" = false ]; then
    echo "[config] config already exists: $CONFIG_FILE" >&2
    echo "[config] use --force to overwrite" >&2
    exit 1
  fi

  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<'CONF'
# jailrun config (machine-specific, not tracked by git)

# --- AWS ---
# allowed AWS profiles (space-separated)
ALLOWED_AWS_PROFILES="default"

# default AWS profile
DEFAULT_AWS_PROFILE="default"

# --- GitHub ---
# short token name — internally expanded to jailrun:github:<name>
# e.g. classic / fine-grained-myorg
GH_TOKEN_NAME="classic"

# --- sandbox customization ---
# additional read-deny paths (space-separated)
# default: ~/.aws ~/.ssh ~/.gnupg ~/.config/gh
#SANDBOX_EXTRA_DENY_READ=""

# additional write-allow paths (space-separated)
# default: ~/.claude ~/.codex ~/.kiro ~/.gemini ~/.cache etc.
#SANDBOX_EXTRA_ALLOW_WRITE=""

# additional write-allow files (space-separated)
#SANDBOX_EXTRA_ALLOW_WRITE_FILES=""

# environment variables to pass through to sandbox (space-separated)
# e.g. SANDBOX_PASSTHROUGH_ENV="ANTHROPIC_API_KEY OPENAI_API_KEY"
#SANDBOX_PASSTHROUGH_ENV=""
CONF
  echo "[config] created: $CONFIG_FILE"
}

# --- dispatch ---
_subcmd="${1:-}"
shift 2>/dev/null || true

case "$_subcmd" in
  show)  _cmd_show ;;
  set)   _cmd_set "$@" ;;
  edit)  _cmd_edit ;;
  path)  _cmd_path ;;
  init)  _cmd_init "$@" ;;
  --help|-h|"")
    cat <<'USAGE'
Usage: jailrun config <subcommand> [options]

Subcommands:
  show                          display current config values
  set KEY VALUE                 update a config key
  set --append KEY VALUE        add a value to a list key
  set --remove KEY VALUE        remove a value from a list key
  edit                          open config in $EDITOR
  path                          print config file path
  init [--force]                generate default config
USAGE
    exit 0
    ;;
  *)
    echo "[config] ERROR: unknown subcommand '$_subcmd'" >&2
    echo "Run 'jailrun config --help' for usage" >&2
    exit 1
    ;;
esac
