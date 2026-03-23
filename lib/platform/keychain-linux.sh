#!/bin/sh
# Retrieve token from Linux GNOME Keyring
# Sourced by credential-guard.sh
#
# Requires: $GH_KEYCHAIN_SERVICE, $_WRAPPER_NAME to be set
# Outputs: $_gh_token, $_gh_token_source

_get_gh_token() {
  _gh_token=""
  _gh_token_source=""
  if command -v secret-tool >/dev/null 2>&1; then
    _gh_token=$(secret-tool lookup service "jailrun:$GH_KEYCHAIN_SERVICE" account "$USER" 2>/dev/null) || true
    [ -n "$_gh_token" ] && _gh_token_source="GNOME Keyring"
  else
    echo "[$_WRAPPER_NAME] WARN: secret-tool not installed (sudo apt install libsecret-tools gnome-keyring)" >&2
  fi
  return 0
}
