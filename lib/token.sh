#!/bin/sh
# トークン管理（macOS Keychain / Linux GNOME Keyring）
# Usage: jailrun token <subcommand> [options]
#
# Keychain サービス名: jailrun:<name>
# 例: jailrun:github:classic → Keychain に "jailrun:github:classic" として保存
# name は "namespace:key" 形式を推奨（例: github:classic, github:fine-grained-myorg）

set -eu

_SERVICE_PREFIX="jailrun"

_service_name() {
  echo "${_SERVICE_PREFIX}:$1"
}

# トークンの先頭12文字を表示用に切り出す
_token_preview() {
  printf '%.12s...' "$1"
}

# ─── OS 別ヘルパー ──────────────────────────────────────

_get_token() {
  local _service="$1"
  case "$(uname)" in
    Darwin)
      security find-generic-password -s "$_service" -a "$USER" -w 2>/dev/null || true
      ;;
    Linux)
      if ! command -v secret-tool >/dev/null 2>&1; then
        echo "ERROR: secret-tool 未インストール (sudo apt install libsecret-tools gnome-keyring)" >&2
        return 1
      fi
      secret-tool lookup service "$_service" account "$USER" 2>/dev/null || true
      ;;
  esac
}

_store_token() {
  local _service="$1" _token="$2"
  case "$(uname)" in
    Darwin)
      security add-generic-password -s "$_service" -a "$USER" -w "$_token"
      ;;
    Linux)
      echo -n "$_token" | secret-tool store --label="$_service" service "$_service" account "$USER"
      ;;
  esac
}

_delete_token() {
  local _service="$1"
  case "$(uname)" in
    Darwin)
      security delete-generic-password -s "$_service" -a "$USER" >/dev/null 2>&1
      ;;
    Linux)
      secret-tool clear service "$_service" account "$USER" 2>/dev/null
      ;;
  esac
}

_check_gh_expiration() {
  local _token="$1"
  local _expires=""
  _expires=$(curl -sS -H "Authorization: Bearer $_token" \
    -D - -o /dev/null https://api.github.com/rate_limit 2>/dev/null \
    | grep -i '^github-authentication-token-expiration:' \
    | sed 's/^[^:]*: *//' | tr -d '\r') || true
  if [ -n "$_expires" ]; then
    echo "$_expires"
  else
    echo "不明"
  fi
}

# ─── サブコマンド ────────────────────────────────────────

_cmd_add() {
  local _name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) _name="$2"; shift 2 ;;
      --name=*) _name="${1#*=}"; shift ;;
      *) echo "[token add] ERROR: unknown option '$1'" >&2; exit 1 ;;
    esac
  done
  if [ -z "$_name" ]; then
    echo "[token add] ERROR: --name is required" >&2
    exit 1
  fi

  local _service _existing
  _service=$(_service_name "$_name")
  _existing=$(_get_token "$_service") || true

  if [ -n "$_existing" ]; then
    echo "[token] '$_name' は既に登録済みです ($(_token_preview "$_existing"))" >&2
    echo "[token] 更新するには 'jailrun token rotate --name $_name' を使ってください" >&2
    exit 1
  fi

  printf '[%s] トークンを入力: ' "$_name"
  stty -echo
  read _token
  stty echo
  echo

  if [ -z "$_token" ]; then
    echo "[$_name] 空のためスキップ"
    return
  fi

  _store_token "$_service" "$_token"
  echo "[$_name] 保存完了 ($(_token_preview "$_token"))"
}

_cmd_rotate() {
  local _name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) _name="$2"; shift 2 ;;
      --name=*) _name="${1#*=}"; shift ;;
      *) echo "[token rotate] ERROR: unknown option '$1'" >&2; exit 1 ;;
    esac
  done
  if [ -z "$_name" ]; then
    echo "[token rotate] ERROR: --name is required" >&2
    exit 1
  fi

  local _service _current
  _service=$(_service_name "$_name")
  _current=$(_get_token "$_service") || true

  if [ -z "$_current" ]; then
    echo "[$_name] トークン未登録" >&2
    echo "[$_name] 'jailrun token add --name $_name' で追加してください" >&2
    exit 1
  fi

  echo "[$_name] 現在のトークン: $(_token_preview "$_current")"
  # GitHub トークンの場合は有効期限を表示
  case "$_name" in
    github:*)
      echo "[$_name] 有効期限: $(_check_gh_expiration "$_current")"
      ;;
  esac
  printf '更新しますか？ [y/N] '
  read _yn
  case "$_yn" in
    [yY]) ;;
    *) echo "スキップ"; return ;;
  esac

  printf '[%s] 新しいトークンを入力: ' "$_name"
  stty -echo
  read _token
  stty echo
  echo

  if [ -z "$_token" ]; then
    echo "[$_name] 空のためスキップ"
    return
  fi

  _delete_token "$_service"
  _store_token "$_service" "$_token"
  echo "[$_name] 更新完了 ($(_token_preview "$_token"))"
}

_cmd_delete() {
  local _name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) _name="$2"; shift 2 ;;
      --name=*) _name="${1#*=}"; shift ;;
      *) echo "[token delete] ERROR: unknown option '$1'" >&2; exit 1 ;;
    esac
  done
  if [ -z "$_name" ]; then
    echo "[token delete] ERROR: --name is required" >&2
    exit 1
  fi

  local _service _current
  _service=$(_service_name "$_name")
  _current=$(_get_token "$_service") || true

  if [ -z "$_current" ]; then
    echo "[$_name] トークン未登録" >&2
    exit 1
  fi

  echo "[$_name] 現在のトークン: $(_token_preview "$_current")"
  printf '削除しますか？ [y/N] '
  read _yn
  case "$_yn" in
    [yY]) ;;
    *) echo "スキップ"; return ;;
  esac

  _delete_token "$_service"
  echo "[$_name] 削除完了"
}

_cmd_list() {
  # Keychain から jailrun: プレフィックスのエントリを列挙
  local _found=false
  case "$(uname)" in
    Darwin)
      # security dump-keychain から jailrun: サービスを抽出
      security dump-keychain 2>/dev/null | grep "\"svce\"<blob>=\"${_SERVICE_PREFIX}:" | while IFS= read -r _line; do
        _svc=$(echo "$_line" | sed "s/.*\"svce\"<blob>=\"//;s/\".*//")
        _name="${_svc#${_SERVICE_PREFIX}:}"
        _token=$(_get_token "$_svc") || true
        if [ -n "$_token" ]; then
          _found=true
          printf '%s\t%s\n' "$_name" "$(_token_preview "$_token")"
        fi
      done
      ;;
    Linux)
      # secret-tool には列挙機能がないため、既知の名前をチェック
      echo "[token list] Linux では既知のトークン名を指定して確認してください" >&2
      echo "  jailrun token rotate --name <name>" >&2
      return
      ;;
  esac
  if [ "$_found" = false ]; then
    echo "登録済みのトークンはありません"
    echo "  jailrun token add --name <name> で追加してください"
  fi
}

# ─── ディスパッチ ────────────────────────────────────────

_subcmd="${1:-}"
shift 2>/dev/null || true

case "$_subcmd" in
  add)     _cmd_add "$@" ;;
  rotate)  _cmd_rotate "$@" ;;
  delete)  _cmd_delete "$@" ;;
  list|ls) _cmd_list "$@" ;;
  --help|-h|"")
    cat <<'USAGE'
Usage: jailrun token <subcommand> [options]

Subcommands:
  add     --name <name>    トークンを新規登録
  rotate  --name <name>    既存トークンをローテーション
  delete  --name <name>    トークンを削除
  list                     登録済みトークン一覧

Examples:
  jailrun token add --name github:classic
  jailrun token add --name github:fine-grained-myorg
  jailrun token rotate --name github:classic
  jailrun token list

Naming convention: <namespace>:<key>
  github:classic              GitHub Classic PAT
  github:fine-grained-myorg   GitHub Fine-grained PAT (org別)

Keychain service name: jailrun:<name>
USAGE
    exit 0
    ;;
  *)
    echo "[token] ERROR: unknown subcommand '$_subcmd'" >&2
    echo "Run 'jailrun token --help' for usage" >&2
    exit 1
    ;;
esac
