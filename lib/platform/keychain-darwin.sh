#!/bin/sh
# Retrieve token from macOS Keychain
# Sourced by credential-guard.sh
#
# Requires: $GH_TOKEN_NAME to be set (short name, e.g. "classic")
# Outputs: $_gh_token, $_gh_token_source

_get_gh_token() {
  _gh_token=""
  _gh_token_source=""
  _gh_token=$(security find-generic-password -s "jailrun:github:$GH_TOKEN_NAME" -a "$USER" -w 2>/dev/null) || true
  [ -n "$_gh_token" ] && _gh_token_source="Keychain"
  return 0
}
