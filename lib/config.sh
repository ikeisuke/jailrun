#!/bin/sh
# config loading (TOML-based via config.py)
# sourced by credential-guard.sh
#
# exports: CONFIG_DIR, CONFIG_FILE, _WRAPPER_NAME,
#          ALLOWED_AWS_PROFILES, DEFAULT_AWS_PROFILE, GH_TOKEN_NAME,
#          _DEFAULT_REGION, SANDBOX_EXTRA_*

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/jailrun"
CONFIG_FILE="$CONFIG_DIR/config.toml"
_WRAPPER_NAME="${WRAPPER_NAME:-jailrun}"

# migration from old directory (pre-TOML era)
_OLD_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/security-wrapper"
if [ ! -f "$CONFIG_FILE" ] && [ -f "$_OLD_CONFIG_DIR/config" ]; then
  mkdir -p "$CONFIG_DIR"
  cp "$_OLD_CONFIG_DIR/config" "$CONFIG_DIR/config"
  echo "[$_WRAPPER_NAME] config migrated: $_OLD_CONFIG_DIR -> $CONFIG_DIR" >&2
fi

# auto-migrate legacy shell config to TOML
_LEGACY_CONFIG="$CONFIG_DIR/config"
if [ ! -f "$CONFIG_FILE" ] && [ -f "$_LEGACY_CONFIG" ]; then
  echo "[$_WRAPPER_NAME] migrating config to TOML format..." >&2
  python3 "$JAILRUN_LIB/config_cli.py" migrate --force 2>&1 | sed "s/^/[$_WRAPPER_NAME] /" >&2
fi

# save caller's env overrides before config overwrites them
_GH_TOKEN_NAME_OVERRIDE="${GH_TOKEN_NAME:-}"
_SANDBOX_PASSTHROUGH_ENV_OVERRIDE="${SANDBOX_PASSTHROUGH_ENV:-}"

# load config via Python (outputs shell-eval format)
if [ -f "$CONFIG_FILE" ]; then
  _config_output="$(python3 "$JAILRUN_LIB/config_cli.py" load --app "$_WRAPPER_NAME" --dir "$PWD")"
  if [ $? -ne 0 ]; then
    echo "[$_WRAPPER_NAME] config error — aborting (check $CONFIG_FILE)" >&2
    exit 1
  fi
  eval "$_config_output"
  unset _config_output
else
  echo "[$_WRAPPER_NAME] config not found: $CONFIG_FILE" >&2
  echo "[$_WRAPPER_NAME] generating initial config..." >&2
  python3 "$JAILRUN_LIB/config_cli.py" init 2>&1 | sed "s/^/[$_WRAPPER_NAME] /" >&2
  echo "[$_WRAPPER_NAME] please review: $CONFIG_FILE" >&2
  exit 1
fi

DEFAULT_AWS_PROFILE="${AWS_PROFILE:-$DEFAULT_AWS_PROFILE}"
_DEFAULT_REGION="${DEFAULT_REGION:-ap-northeast-1}"

# runtime override: GH_TOKEN_NAME=<name> jailrun claude
GH_TOKEN_NAME="${_GH_TOKEN_NAME_OVERRIDE:-$GH_TOKEN_NAME}"
unset _GH_TOKEN_NAME_OVERRIDE

# restore passthrough env if caller had it set
if [ -n "$_SANDBOX_PASSTHROUGH_ENV_OVERRIDE" ]; then
  SANDBOX_PASSTHROUGH_ENV="$_SANDBOX_PASSTHROUGH_ENV_OVERRIDE"
fi
unset _SANDBOX_PASSTHROUGH_ENV_OVERRIDE
