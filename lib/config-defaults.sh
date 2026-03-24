#!/bin/sh
# Shared config defaults and template
# Sourced by config.sh and config-cmd.sh

# known config keys (space-separated)
_KNOWN_KEYS="ALLOWED_AWS_PROFILES DEFAULT_AWS_PROFILE GH_TOKEN_NAME SANDBOX_EXTRA_DENY_READ SANDBOX_EXTRA_ALLOW_WRITE SANDBOX_EXTRA_ALLOW_WRITE_FILES SANDBOX_PASSTHROUGH_ENV"

# list-type keys (support --append / --remove)
_LIST_KEYS="ALLOWED_AWS_PROFILES SANDBOX_EXTRA_DENY_READ SANDBOX_EXTRA_ALLOW_WRITE SANDBOX_EXTRA_ALLOW_WRITE_FILES SANDBOX_PASSTHROUGH_ENV"

_load_config_defaults() {
  ALLOWED_AWS_PROFILES=""
  DEFAULT_AWS_PROFILE=""
  GH_TOKEN_NAME="classic"
  SANDBOX_EXTRA_DENY_READ=""
  SANDBOX_EXTRA_ALLOW_WRITE=""
  SANDBOX_EXTRA_ALLOW_WRITE_FILES=""
  SANDBOX_PASSTHROUGH_ENV=""
}

_write_default_config() {
  cat > "$1" <<'CONF'
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
}
