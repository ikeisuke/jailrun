#!/bin/sh
# config loading and validation
# sourced by credential-guard.sh
#
# exports: CONFIG_DIR, CONFIG_FILE, _WRAPPER_NAME,
#          ALLOWED_AWS_PROFILES, DEFAULT_AWS_PROFILE, GH_TOKEN_NAME,
#          _DEFAULT_REGION, SANDBOX_EXTRA_*

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/jailrun"
CONFIG_FILE="$CONFIG_DIR/config"
_WRAPPER_NAME="${WRAPPER_NAME:-jailrun}"

# migration from old directory
_OLD_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/security-wrapper"
if [ ! -f "$CONFIG_FILE" ] && [ -f "$_OLD_CONFIG_DIR/config" ]; then
  mkdir -p "$CONFIG_DIR"
  cp "$_OLD_CONFIG_DIR/config" "$CONFIG_FILE"
  echo "[$_WRAPPER_NAME] config migrated: $_OLD_CONFIG_DIR -> $CONFIG_DIR" >&2
fi

# save caller's env overrides before defaults overwrite them
_GH_TOKEN_NAME_OVERRIDE="${GH_TOKEN_NAME:-}"
_SANDBOX_PASSTHROUGH_ENV_OVERRIDE="${SANDBOX_PASSTHROUGH_ENV:-}"

# defaults (JAILRUN_LIB is set by bin/jailrun before this file is sourced)
. "$JAILRUN_LIB/config-defaults.sh"
_load_config_defaults
_DEFAULT_REGION="ap-northeast-1"
SANDBOX_PASSTHROUGH_ENV="$_SANDBOX_PASSTHROUGH_ENV_OVERRIDE"
unset _SANDBOX_PASSTHROUGH_ENV_OVERRIDE

# load or generate config
if [ -f "$CONFIG_FILE" ]; then
  . "$CONFIG_FILE"
  # migrate legacy GH_KEYCHAIN_SERVICE -> GH_TOKEN_NAME
  # only apply if config has GH_KEYCHAIN_SERVICE but NOT GH_TOKEN_NAME
  if [ -n "${GH_KEYCHAIN_SERVICE:-}" ] && ! grep -qE '(^|export[[:space:]]+)GH_TOKEN_NAME=' "$CONFIG_FILE" 2>/dev/null; then
    # strip "github:" prefix if present (e.g. "github:classic" -> "classic")
    case "$GH_KEYCHAIN_SERVICE" in
      github:*) GH_TOKEN_NAME="${GH_KEYCHAIN_SERVICE#github:}" ;;
      *)        GH_TOKEN_NAME="$GH_KEYCHAIN_SERVICE" ;;
    esac
    echo "[$_WRAPPER_NAME] WARN: GH_KEYCHAIN_SERVICE is deprecated, use GH_TOKEN_NAME=\"$GH_TOKEN_NAME\" instead" >&2
  fi
else
  echo "[$_WRAPPER_NAME] config not found: $CONFIG_FILE" >&2
  echo "[$_WRAPPER_NAME] generating initial config..." >&2
  mkdir -p "$CONFIG_DIR"

  _write_default_config "$CONFIG_FILE"
  echo "[$_WRAPPER_NAME] created: $CONFIG_FILE" >&2
  echo "[$_WRAPPER_NAME] please review: $CONFIG_FILE" >&2
  exit 1
fi

DEFAULT_AWS_PROFILE="${AWS_PROFILE:-$DEFAULT_AWS_PROFILE}"

# runtime override: GH_TOKEN_NAME=<name> jailrun claude
GH_TOKEN_NAME="${_GH_TOKEN_NAME_OVERRIDE:-$GH_TOKEN_NAME}"
unset _GH_TOKEN_NAME_OVERRIDE
