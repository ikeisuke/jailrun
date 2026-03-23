#!/bin/zsh
# macOS Keychain からトークンを取得
# credential-guard.sh から source される
#
# 前提: $GH_KEYCHAIN_SERVICE が設定済みであること
# 出力: $_gh_token, $_gh_token_source

_get_gh_token() {
  _gh_token=""
  _gh_token_source=""
  _gh_token=$(security find-generic-password -s "jailrun:$GH_KEYCHAIN_SERVICE" -a "$USER" -w 2>/dev/null) || true
  [[ -n "$_gh_token" ]] && _gh_token_source="Keychain"
  return 0
}
