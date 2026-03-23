#!/usr/bin/env bats

load helpers

@test "_resolve_real_bin strips shims from PATH" {
  setup_jailrun_env

  # Create a fake binary in a temp dir
  tmpbin=$(mktemp -d)
  printf '#!/bin/sh\n' > "$tmpbin/claude"
  chmod +x "$tmpbin/claude"

  # Create a fake shims dir
  tmpshims=$(mktemp -d)/jailrun/shims
  mkdir -p "$tmpshims"
  printf '#!/bin/sh\n' > "$tmpshims/claude"
  chmod +x "$tmpshims/claude"

  # Test the PATH cleaning logic directly (no sourcing needed)
  run sh -c '
    WRAPPER_NAME=claude
    PATH="'"$tmpshims"':'"$tmpbin"':/usr/bin"
    _clean_path=""
    _OLD_IFS="$IFS"; IFS=":"
    for _d in $PATH; do
      case "$_d" in
        */jailrun/shims) ;;
        *) _clean_path="${_clean_path:+$_clean_path:}$_d" ;;
      esac
    done
    IFS="$_OLD_IFS"
    REAL_BIN=$(PATH="$_clean_path" command -v "$WRAPPER_NAME" 2>/dev/null) || true
    echo "$REAL_BIN"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "$tmpbin/claude" ]]

  rm -rf "$tmpbin" "$(dirname "$tmpshims")"
}

@test "PATH cleaning preserves non-shim entries" {
  run sh -c '
    PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin"
    _clean_path=""
    _OLD_IFS="$IFS"; IFS=":"
    for _d in $PATH; do
      case "$_d" in
        */jailrun/shims) ;;
        *) _clean_path="${_clean_path:+$_clean_path:}$_d" ;;
      esac
    done
    IFS="$_OLD_IFS"
    echo "$_clean_path"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/local/bin:/opt/homebrew/bin:/usr/bin" ]
}

@test "PATH cleaning removes multiple shim entries" {
  run sh -c '
    PATH="/foo/jailrun/shims:/usr/bin:/bar/jailrun/shims:/opt/bin"
    _clean_path=""
    _OLD_IFS="$IFS"; IFS=":"
    for _d in $PATH; do
      case "$_d" in
        */jailrun/shims) ;;
        *) _clean_path="${_clean_path:+$_clean_path:}$_d" ;;
      esac
    done
    IFS="$_OLD_IFS"
    echo "$_clean_path"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/bin:/opt/bin" ]
}
