#!/usr/bin/env bats

# Cycle v0.3.6 / Unit 001 / Issue #78
#
# Verifies that lib/sandbox.sh constructs _SANDBOX_ALLOW_WRITE_LOCK_PATHS
# correctly for kiro-cli (~/.kiro, ~/.local/share, $XDG_RUNTIME_DIR/kiro-log)
# and that ~/.kiro / ~/.local/share are removed from _SANDBOX_ALLOW_WRITE_PATHS.
#
# These tests are platform-agnostic at the variable-construction layer:
# sandbox.sh dispatches to a platform backend at the end of the script,
# so this file stubs the dispatch by providing a fake JAILRUN_LIB pointing
# to minimal platform/*.sh files.

load helpers

setup() {
  setup_jailrun_env
  _fake_lib="$(mktemp -d)"
  export _fake_lib

  # Mirror lib/ structure with the real sandbox.sh plus stubbed platform backends.
  mkdir -p "$_fake_lib/platform"
  cp "$JAILRUN_LIB/sandbox.sh" "$_fake_lib/sandbox.sh"
  printf '#!/bin/sh\n# stub for tests\n' > "$_fake_lib/platform/sandbox-darwin.sh"
  printf '#!/bin/sh\n# stub for tests\n' > "$_fake_lib/platform/sandbox-linux.sh"

  _fake_home="$(mktemp -d)"
  export _fake_home
}

teardown() {
  rm -rf "$_fake_lib" "$_fake_home"
}

# Run sandbox.sh variable construction in an isolated env and dump the
# requested variable to stdout (one entry per line, empty entries stripped).
_dump_sandbox_var() {
  local _var="$1"
  shift
  env -i HOME="$_fake_home" JAILRUN_LIB="$_fake_lib" PATH="$PATH" "$@" sh -c "
    _tmpdir=\"\$(mktemp -d)\"
    _WRAPPER_NAME=claude
    . \"$_fake_lib/sandbox.sh\"
    printf '%s\n' \"\$$_var\"
    rm -rf \"\$_tmpdir\"
  " | sed '/^[[:space:]]*$/d'
}

# Helper: assert <path> appears in the variable's listing.
_assert_var_contains() {
  local _var="$1" _expected="$2"
  shift 2
  local _output
  _output="$(_dump_sandbox_var "$_var" "$@")"
  if ! printf '%s\n' "$_output" | grep -Fxq "$_expected"; then
    printf 'Expected %s to contain:\n  %s\nActual:\n%s\n' \
      "$_var" "$_expected" "$_output" >&2
    return 1
  fi
}

# Helper: assert <path> does NOT appear in the variable's listing.
_assert_var_excludes() {
  local _var="$1" _excluded="$2"
  shift 2
  local _output
  _output="$(_dump_sandbox_var "$_var" "$@")"
  if printf '%s\n' "$_output" | grep -Fxq "$_excluded"; then
    printf 'Expected %s to exclude:\n  %s\nActual:\n%s\n' \
      "$_var" "$_excluded" "$_output" >&2
    return 1
  fi
}

@test "sandbox.sh puts ~/.kiro into LOCK_PATHS (not WRITE_PATHS)" {
  _assert_var_contains _SANDBOX_ALLOW_WRITE_LOCK_PATHS "$_fake_home/.kiro"
  _assert_var_excludes _SANDBOX_ALLOW_WRITE_PATHS "$_fake_home/.kiro"
}

@test "sandbox.sh puts ~/.local/share into LOCK_PATHS (not WRITE_PATHS)" {
  _assert_var_contains _SANDBOX_ALLOW_WRITE_LOCK_PATHS "$_fake_home/.local/share"
  _assert_var_excludes _SANDBOX_ALLOW_WRITE_PATHS "$_fake_home/.local/share"
}

@test "sandbox.sh adds \$XDG_RUNTIME_DIR/kiro-log to LOCK_PATHS when XDG_RUNTIME_DIR is set" {
  _xdg="$(mktemp -d)"
  _assert_var_contains _SANDBOX_ALLOW_WRITE_LOCK_PATHS "$_xdg/kiro-log" XDG_RUNTIME_DIR="$_xdg"
  rm -rf "$_xdg"
}

@test "sandbox.sh skips kiro-log when XDG_RUNTIME_DIR is unset" {
  _output="$(_dump_sandbox_var _SANDBOX_ALLOW_WRITE_LOCK_PATHS)"
  if printf '%s\n' "$_output" | grep -q 'kiro-log'; then
    printf 'Unexpected kiro-log entry without XDG_RUNTIME_DIR:\n%s\n' "$_output" >&2
    return 1
  fi
}

@test "sandbox.sh retains existing proper-lockfile lock paths" {
  _assert_var_contains _SANDBOX_ALLOW_WRITE_LOCK_PATHS "$_fake_home/.claude.lock"
  _assert_var_contains _SANDBOX_ALLOW_WRITE_LOCK_PATHS "$_fake_home/.claude.json.lock"
}
