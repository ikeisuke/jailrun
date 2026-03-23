#!/bin/sh
# Retrieve token from macOS Keychain
# Sourced by credential-guard.sh
#
# Requires: $GH_KEYCHAIN_SERVICE to be set
# Outputs: $_gh_token, $_gh_token_source

_get_gh_token() {
  _gh_token=""
  _gh_token_source=""
  _gh_token=$(security find-generic-password -s "jailrun:$GH_KEYCHAIN_SERVICE" -a "$USER" -w 2>/dev/null) || true
  [ -n "$_gh_token" ] && _gh_token_source="Keychain"
  return 0
}
