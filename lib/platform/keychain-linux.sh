#!/bin/sh
# Retrieve token from Linux GNOME Keyring
# Sourced by credential-guard.sh
#
# Requires: $GH_TOKEN_NAME, $_WRAPPER_NAME to be set (short name, e.g. "classic")
# Outputs: $_gh_token, $_gh_token_source

_get_gh_token() {
  _gh_token=""
  _gh_token_source=""
  if command -v secret-tool >/dev/null 2>&1; then
    _gh_token=$(secret-tool lookup service "jailrun:github:$GH_TOKEN_NAME" account "$USER" 2>/dev/null) || true
    [ -n "$_gh_token" ] && _gh_token_source="GNOME Keyring"
  else
    echo "[$_WRAPPER_NAME] WARN: secret-tool not installed (sudo apt install libsecret-tools gnome-keyring)" >&2
  fi
  return 0
}
