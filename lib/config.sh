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

# save caller's env override before defaults overwrite it
_GH_TOKEN_NAME_OVERRIDE="${GH_TOKEN_NAME:-}"

# defaults
ALLOWED_AWS_PROFILES=""
DEFAULT_AWS_PROFILE=""
GH_TOKEN_NAME="classic"
_DEFAULT_REGION="ap-northeast-1"

SANDBOX_EXTRA_DENY_READ=""
SANDBOX_EXTRA_ALLOW_WRITE=""
SANDBOX_EXTRA_ALLOW_WRITE_FILES=""
SANDBOX_PASSTHROUGH_ENV="${SANDBOX_PASSTHROUGH_ENV:-}"

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
  echo "[$_WRAPPER_NAME] created: $CONFIG_FILE" >&2
  echo "[$_WRAPPER_NAME] please review: $CONFIG_FILE" >&2
  exit 1
fi

DEFAULT_AWS_PROFILE="${AWS_PROFILE:-$DEFAULT_AWS_PROFILE}"

# runtime override: GH_TOKEN_NAME=<name> jailrun claude
GH_TOKEN_NAME="${_GH_TOKEN_NAME_OVERRIDE:-$GH_TOKEN_NAME}"
unset _GH_TOKEN_NAME_OVERRIDE
