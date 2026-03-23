#!/bin/sh
# Token management (macOS Keychain / Linux GNOME Keyring)
# Usage: jailrun token <subcommand> [options]
#
# Keychain service name: jailrun:<name>
# Example: jailrun:github:classic -> stored as "jailrun:github:classic" in Keychain
# Recommended name format: "namespace:key" (e.g., github:classic, github:fine-grained-myorg)

set -eu

_SERVICE_PREFIX="jailrun"

_service_name() {
  echo "${_SERVICE_PREFIX}:$1"
}

# Extract the first 12 characters of a token for display
_token_preview() {
  printf '%.12s...' "$1"
}

# --- OS-specific helpers ---

_get_token() {
  local _service="$1"
  case "$(uname)" in
    Darwin)
      security find-generic-password -s "$_service" -a "$USER" -w 2>/dev/null || true
      ;;
    Linux)
      if ! command -v secret-tool >/dev/null 2>&1; then
        echo "ERROR: secret-tool not installed (sudo apt install libsecret-tools gnome-keyring)" >&2
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
    echo "unknown"
  fi
}

# --- Subcommands ---

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
    echo "[token] '$_name' is already registered ($(_token_preview "$_existing"))" >&2
    echo "[token] use 'jailrun token rotate --name $_name' to update" >&2
    exit 1
  fi

  printf '[%s] Enter token: ' "$_name"
  if [ -t 0 ]; then stty -echo; fi
  read _token
  if [ -t 0 ]; then stty echo; echo; fi

  if [ -z "$_token" ]; then
    echo "[$_name] empty input, skipping"
    return
  fi

  _store_token "$_service" "$_token"
  echo "[$_name] saved ($(_token_preview "$_token"))"
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
    echo "[$_name] token not registered" >&2
    echo "[$_name] use 'jailrun token add --name $_name' to add" >&2
    exit 1
  fi

  echo "[$_name] current token: $(_token_preview "$_current")"
  # Show expiration for GitHub tokens
  case "$_name" in
    github:*)
      echo "[$_name] expiration: $(_check_gh_expiration "$_current")"
      ;;
  esac
  printf 'Update? [y/N] '
  read _yn
  case "$_yn" in
    [yY]) ;;
    *) echo "skipped"; return ;;
  esac

  printf '[%s] Enter new token: ' "$_name"
  stty -echo
  read _token
  stty echo
  echo

  if [ -z "$_token" ]; then
    echo "[$_name] empty input, skipping"
    return
  fi

  _delete_token "$_service"
  _store_token "$_service" "$_token"
  echo "[$_name] updated ($(_token_preview "$_token"))"
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
    echo "[$_name] token not registered" >&2
    exit 1
  fi

  echo "[$_name] current token: $(_token_preview "$_current")"
  printf 'Delete? [y/N] '
  read _yn
  case "$_yn" in
    [yY]) ;;
    *) echo "skipped"; return ;;
  esac

  _delete_token "$_service"
  echo "[$_name] deleted"
}

_cmd_list() {
  # List entries with jailrun: prefix from keychain
  case "$(uname)" in
    Darwin)
      # Extract jailrun: services from security dump-keychain
      # Use temp file to avoid subshell variable scoping with pipe
      _list_tmp=$(mktemp)
      security dump-keychain 2>/dev/null | grep "\"svce\"<blob>=\"${_SERVICE_PREFIX}:" | sed "s/.*\"svce\"<blob>=\"//;s/\".*//" > "$_list_tmp"
      _found=false
      while IFS= read -r _svc; do
        _name="${_svc#${_SERVICE_PREFIX}:}"
        _token=$(_get_token "$_svc") || true
        if [ -n "$_token" ]; then
          _found=true
          printf '%s\t%s\n' "$_name" "$(_token_preview "$_token")"
        fi
      done < "$_list_tmp"
      rm -f "$_list_tmp"
      if [ "$_found" = false ]; then
        echo "no tokens registered"
        echo "  use 'jailrun token add --name <name>' to add one"
      fi
      ;;
    Linux)
      # secret-tool has no enumeration capability; check known names
      echo "[token list] on Linux, specify a known token name to check" >&2
      echo "  jailrun token rotate --name <name>" >&2
      ;;
  esac
}

# --- Dispatch ---

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
  add     --name <name>    Register a new token
  rotate  --name <name>    Rotate an existing token
  delete  --name <name>    Delete a token
  list                     List registered tokens

Examples:
  jailrun token add --name github:classic
  jailrun token add --name github:fine-grained-myorg
  jailrun token rotate --name github:classic
  jailrun token list

Naming convention: <namespace>:<key>
  github:classic              GitHub Classic PAT
  github:fine-grained-myorg   GitHub Fine-grained PAT (per-org)

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
