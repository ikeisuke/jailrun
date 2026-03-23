#!/bin/zsh
# Linux GNOME Keyring からトークンを取得
# credential-guard.sh から source される
#
# 前提: $GH_KEYCHAIN_SERVICE, $_WRAPPER_NAME が設定済みであること
# 出力: $_gh_token, $_gh_token_source

_get_gh_token() {
  _gh_token=""
  _gh_token_source=""
  if command -v secret-tool >/dev/null 2>&1; then
    _gh_token=$(secret-tool lookup service "jailrun:$GH_KEYCHAIN_SERVICE" account "$USER" 2>/dev/null) || true
    [[ -n "$_gh_token" ]] && _gh_token_source="GNOME Keyring"
  else
    echo "[$_WRAPPER_NAME] WARN: secret-tool 未インストール (sudo apt install libsecret-tools gnome-keyring)" >&2
  fi
  return 0
}
