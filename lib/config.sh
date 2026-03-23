#!/bin/sh
# config loading and validation
# sourced by credential-guard.sh
#
# exports: CONFIG_DIR, CONFIG_FILE, _WRAPPER_NAME,
#          ALLOWED_AWS_PROFILES, DEFAULT_AWS_PROFILE, GH_KEYCHAIN_SERVICE,
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

# defaults
ALLOWED_AWS_PROFILES=""
DEFAULT_AWS_PROFILE=""
GH_KEYCHAIN_SERVICE="github:classic"
_DEFAULT_REGION="ap-northeast-1"

SANDBOX_EXTRA_DENY_READ=""
SANDBOX_EXTRA_ALLOW_WRITE=""
SANDBOX_EXTRA_ALLOW_WRITE_FILES=""

# load or generate config
if [ -f "$CONFIG_FILE" ]; then
  . "$CONFIG_FILE"
else
  echo "[$_WRAPPER_NAME] config not found: $CONFIG_FILE" >&2
  echo "[$_WRAPPER_NAME] generating initial config..." >&2
  mkdir -p "$CONFIG_DIR"

  cat > "$CONFIG_FILE" <<'CONF'
# jailrun config (machine-specific, not tracked by git)

# --- AWS ---
# allowed AWS profiles (space-separated)
ALLOWED_AWS_PROFILES="default"

# default AWS profile
DEFAULT_AWS_PROFILE="default"

# --- GitHub ---
# token name registered via `jailrun token`
# github:fine-grained-myorg / github:classic
GH_KEYCHAIN_SERVICE="github:classic"

# --- sandbox customization ---
# additional read-deny paths (space-separated)
# default: ~/.aws ~/.ssh ~/.gnupg ~/.config/gh
#SANDBOX_EXTRA_DENY_READ=""

# additional write-allow paths (space-separated)
# default: ~/.claude ~/.codex ~/.kiro ~/.gemini ~/.cache etc.
#SANDBOX_EXTRA_ALLOW_WRITE=""

# additional write-allow files (space-separated)
#SANDBOX_EXTRA_ALLOW_WRITE_FILES=""
CONF
  echo "[$_WRAPPER_NAME] created: $CONFIG_FILE" >&2
  echo "[$_WRAPPER_NAME] please review: $CONFIG_FILE" >&2
  exit 1
fi

DEFAULT_AWS_PROFILE="${AGENT_AWS_PROFILE:-${AWS_PROFILE:-$DEFAULT_AWS_PROFILE}}"
