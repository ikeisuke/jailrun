#!/bin/sh
# Shared config defaults and template
# Legacy/dead fallback template; the current TOML path uses config_cli.py
# (this file is not sourced by config.sh or config-cmd.sh anymore).

# known config keys (space-separated)
_KNOWN_KEYS="ALLOWED_AWS_PROFILES DEFAULT_AWS_PROFILE GH_TOKEN_NAME SANDBOX_EXTRA_DENY_READ SANDBOX_EXTRA_ALLOW_WRITE SANDBOX_EXTRA_ALLOW_WRITE_FILES SANDBOX_PASSTHROUGH_ENV SANDBOX_SECRET_INJECT"

# list-type keys (support --append / --remove)
_LIST_KEYS="ALLOWED_AWS_PROFILES SANDBOX_EXTRA_DENY_READ SANDBOX_EXTRA_ALLOW_WRITE SANDBOX_EXTRA_ALLOW_WRITE_FILES SANDBOX_PASSTHROUGH_ENV SANDBOX_SECRET_INJECT"

_load_config_defaults() {
  ALLOWED_AWS_PROFILES=""
  DEFAULT_AWS_PROFILE=""
  GH_TOKEN_NAME="classic"
  SANDBOX_EXTRA_DENY_READ=""
  SANDBOX_EXTRA_ALLOW_WRITE=""
  SANDBOX_EXTRA_ALLOW_WRITE_FILES=""
  SANDBOX_PASSTHROUGH_ENV=""
  SANDBOX_SECRET_INJECT=""
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

# inject secrets from the keychain as env vars (ENVVAR:identifier, space-separated)
# e.g. SANDBOX_SECRET_INJECT="OPENAI_API_KEY:default ANTHROPIC_API_KEY:work"
#SANDBOX_SECRET_INJECT=""
CONF
}
