#!/usr/bin/env bats

# Tests for lib/platform/sandbox-linux-apparmor.sh
# Verifies AppArmor profile generation and systemd integration.
# These tests run on any platform (profile generation is pure text output).

load helpers

setup() {
  setup_jailrun_env
  _tmpdir=$(mktemp -d)
  export _tmpdir
}

teardown() {
  rm -rf "$_tmpdir"
}

# Semantic assertion helpers — verify that the generated AppArmor profile
# contains (or does not contain) a rule for <path> with <permission>.
# The helpers encapsulate the quote-inside-glob format (e.g. "/foo/**" rwk,)
# so individual @tests stay decoupled from the textual layout.
#
# Usage:
#   assert_profile_has_rule "$_aa" "$HOME/.kiro" "rwk"
#   assert_profile_no_rule  "$_aa" "$HOME/.something" "rwk"
assert_profile_has_rule() {
  local _aa="$1" _path="$2" _perm="$3"
  local _glob="\"${_path}/**\" ${_perm},"
  [[ "$_aa" == *"$_glob"* ]]
}

assert_profile_no_rule() {
  local _aa="$1" _path="$2" _perm="$3"
  local _glob="\"${_path}/**\" ${_perm},"
  [[ "$_aa" != *"$_glob"* ]]
}

# Helper: run _setup_sandbox with AppArmor enabled, output both files
run_setup_with_apparmor() {
  run sh -c '
    _tmpdir="'"$_tmpdir"'"
    _git_parent_toplevel="'"${_git_parent_toplevel:-}"'"
    _git_common_dir="'"${_git_common_dir:-}"'"
    _other_worktrees="'"${_other_worktrees:-}"'"
    _SANDBOX_ALLOW_WRITE_PATHS="'"${_SANDBOX_ALLOW_WRITE_PATHS:-}"'"
    _SANDBOX_ALLOW_WRITE_LOCK_PATHS="'"${_SANDBOX_ALLOW_WRITE_LOCK_PATHS:-}"'"
    _SANDBOX_ALLOW_WRITE_FILES="'"${_SANDBOX_ALLOW_WRITE_FILES:-}"'"
    _SANDBOX_DENY_READ_PATHS="'"${_SANDBOX_DENY_READ_PATHS:-}"'"
    _WRAPPER_NAME="claude"
    _APPARMOR_AVAILABLE=1
    export PROXY_ENABLED="'"${PROXY_ENABLED:-false}"'"
    _detect_git_worktree() { :; }
    . "'"$JAILRUN_LIB"'/platform/sandbox-linux-apparmor.sh"
    # Override _load to succeed without sudo
    _load_apparmor_profile() { _APPARMOR_PROFILE_LOADED=1; return 0; }
    . "'"$JAILRUN_LIB"'/platform/sandbox-linux-systemd.sh"
    _setup_sandbox
    echo "=== APPARMOR ==="
    cat "$_tmpdir/apparmor-profile"
    echo "=== PROPS ==="
    cat "$_tmpdir/systemd-props"
  '
}

# Helper: extract AppArmor profile section from output
get_apparmor() {
  echo "$output" | sed -n '/=== APPARMOR ===/,/=== PROPS ===/p' | sed '1d;$d'
}

# Helper: extract systemd-props section from output
get_props() {
  echo "$output" | sed -n '/=== PROPS ===/,$p' | sed '1d'
}

# --- AppArmor profile structure ---

@test "apparmor profile includes header and abstractions" {
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _aa=$(get_apparmor)
  [[ "$_aa" == *"#include <tunables/global>"* ]]
  [[ "$_aa" == *"#include <abstractions/base>"* ]]
  [[ "$_aa" == *"profile jailrun_"* ]]
  [[ "$_aa" == *"flags=(attach_disconnected)"* ]]
}

@test "apparmor profile allows read and execute by default" {
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _aa=$(get_apparmor)
  [[ "$_aa" == *"/** r,"* ]]
  [[ "$_aa" == *"/** ix,"* ]]
}

@test "apparmor profile denies read for sensitive paths" {
  _SANDBOX_DENY_READ_PATHS="/home/testuser/.aws
/home/testuser/.ssh"
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _aa=$(get_apparmor)
  [[ "$_aa" == *'deny "/home/testuser/.aws/**" r,'* ]]
  [[ "$_aa" == *'deny "/home/testuser/.ssh/**" r,'* ]]
}

@test "apparmor profile denies read for non-existent paths" {
  _SANDBOX_DENY_READ_PATHS="/nonexistent/secret/path"
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _aa=$(get_apparmor)
  # Unlike systemd InaccessiblePaths, AppArmor handles non-existent paths
  [[ "$_aa" == *'deny "/nonexistent/secret/path/**" r,'* ]]
}

@test "apparmor profile includes write whitelist for cwd and tmp" {
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _aa=$(get_apparmor)
  [[ "$_aa" == *"/tmp/** rw,"* ]]
  [[ "$_aa" == *'/**" rwk,'* ]]
}

@test "apparmor profile denies D-Bus socket" {
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _aa=$(get_apparmor)
  [[ "$_aa" == *"deny /run/user/*/bus rw,"* ]]
}

@test "apparmor profile denies writes to config directory" {
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _aa=$(get_apparmor)
  [[ "$_aa" == *'deny "'*'/jailrun/**" w,'* ]]
}

# --- Deny-read filename patterns ---

@test "apparmor profile includes deny-read filename pattern from regexes" {
  run sh -c '
    _tmpdir="'"$_tmpdir"'"
    _git_parent_toplevel=""
    _git_common_dir=""
    _other_worktrees=""
    _SANDBOX_ALLOW_WRITE_PATHS=""
    _SANDBOX_ALLOW_WRITE_LOCK_PATHS=""
    _SANDBOX_ALLOW_WRITE_FILES=""
    _SANDBOX_DENY_READ_PATHS=""
    _SANDBOX_DENY_READ_REGEXES="/\.env\$"
    _WRAPPER_NAME="claude"
    _APPARMOR_AVAILABLE=1
    export PROXY_ENABLED=false
    _detect_git_worktree() { :; }
    . "'"$JAILRUN_LIB"'/platform/sandbox-linux-apparmor.sh"
    _load_apparmor_profile() { _APPARMOR_PROFILE_LOADED=1; return 0; }
    . "'"$JAILRUN_LIB"'/platform/sandbox-linux-systemd.sh"
    _setup_sandbox
    cat "$_tmpdir/apparmor-profile"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"deny /**/.env r,"* ]]
}

# --- Git worktree integration ---

@test "apparmor profile includes git parent toplevel as writable" {
  _wt_dir=$(mktemp -d)
  _git_parent_toplevel="$_wt_dir"
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _aa=$(get_apparmor)
  [[ "$_aa" == *"\"$_wt_dir/**\" rwk,"* ]]
  rm -rf "$_wt_dir"
}

@test "apparmor profile denies writes to other worktrees" {
  _other="$(mktemp -d)"
  _other_worktrees="$_other"
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _aa=$(get_apparmor)
  [[ "$_aa" == *"deny \"$_other/**\" w,"* ]]
  rm -rf "$_other"
}

# --- New (v0.3.6 / Issue #78): lock-required directory rwk emission ---

@test "apparmor profile emits rwk rule for ~/.kiro when present in LOCK_PATHS" {
  _kiro_dir="$(mktemp -d)/kiro"
  _SANDBOX_ALLOW_WRITE_LOCK_PATHS="$_kiro_dir"
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _aa=$(get_apparmor)
  assert_profile_has_rule "$_aa" "$_kiro_dir" "rwk"
  rm -rf "$(dirname "$_kiro_dir")"
}

@test "apparmor profile emits rwk rule for ~/.local/share when present in LOCK_PATHS" {
  _share_dir="$(mktemp -d)/local-share"
  _SANDBOX_ALLOW_WRITE_LOCK_PATHS="$_share_dir"
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _aa=$(get_apparmor)
  assert_profile_has_rule "$_aa" "$_share_dir" "rwk"
  rm -rf "$(dirname "$_share_dir")"
}

@test "apparmor profile emits rwk rule for kiro-log when XDG_RUNTIME_DIR is set" {
  _xdg_dir="$(mktemp -d)"
  _kiro_log="$_xdg_dir/kiro-log"
  _SANDBOX_ALLOW_WRITE_LOCK_PATHS="$_kiro_log"
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _aa=$(get_apparmor)
  assert_profile_has_rule "$_aa" "$_kiro_log" "rwk"
  rm -rf "$_xdg_dir"
}

# Regression: confirm the profile has no quote-outside-glob form
# (e.g. `"path"/**` or `"path"/`). AppArmor 3.0.4 rejects this syntax.
@test "apparmor profile contains no quote-outside-glob form (Issue #78 regression)" {
  _SANDBOX_DENY_READ_PATHS="/home/testuser/.aws"
  _SANDBOX_ALLOW_WRITE_PATHS="/home/testuser/.cache"
  _SANDBOX_ALLOW_WRITE_LOCK_PATHS="/home/testuser/.kiro"
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _aa=$(get_apparmor)
  # Old format `"path"/...` (closing quote immediately followed by slash) must not appear.
  # The grep is anchored to the boundary between quote and slash. Allow lines like
  # `"path/" rw,` (slash inside the quote) but reject `"path"/ rw,`.
  if printf '%s\n' "$_aa" | grep -qE '"[^"]+"/'; then
    printf 'Found quote-outside-glob form in profile:\n%s\n' "$_aa" >&2
    return 1
  fi
}

# --- systemd integration (AppArmor active) ---

@test "systemd props omit ProtectSystem when AppArmor active" {
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _props=$(get_props)
  [[ "$_props" != *"ProtectSystem=strict"* ]]
}

@test "systemd props omit ProtectHome when AppArmor active" {
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _props=$(get_props)
  [[ "$_props" != *"ProtectHome=read-only"* ]]
}

@test "systemd props omit InaccessiblePaths when AppArmor active" {
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _props=$(get_props)
  [[ "$_props" != *"InaccessiblePaths="* ]]
}

@test "systemd props include AppArmorProfile when AppArmor active" {
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _props=$(get_props)
  [[ "$_props" == *"AppArmorProfile=jailrun_"* ]]
}

@test "systemd props retain non-FS properties when AppArmor active" {
  run_setup_with_apparmor
  [ "$status" -eq 0 ]
  _props=$(get_props)
  [[ "$_props" == *"NoNewPrivileges=yes"* ]]
  [[ "$_props" == *"CapabilityBoundingSet="* ]]
  [[ "$_props" == *"SystemCallFilter=@system-service"* ]]
  [[ "$_props" == *"ProtectKernelLogs=yes"* ]]
  [[ "$_props" == *"RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6"* ]]
}

# --- Fallback (AppArmor load fails) ---

@test "systemd props include ProtectSystem when AppArmor load fails" {
  run sh -c '
    _tmpdir="'"$_tmpdir"'"
    _git_parent_toplevel=""
    _git_common_dir=""
    _other_worktrees=""
    _SANDBOX_ALLOW_WRITE_PATHS=""
    _SANDBOX_ALLOW_WRITE_LOCK_PATHS=""
    _SANDBOX_ALLOW_WRITE_FILES=""
    _SANDBOX_DENY_READ_PATHS=""
    _WRAPPER_NAME="claude"
    _APPARMOR_AVAILABLE=1
    export PROXY_ENABLED=false
    _detect_git_worktree() { :; }
    . "'"$JAILRUN_LIB"'/platform/sandbox-linux-apparmor.sh"
    # Override _load to fail (simulates no sudo access)
    _load_apparmor_profile() { _APPARMOR_PROFILE_LOADED=""; return 1; }
    . "'"$JAILRUN_LIB"'/platform/sandbox-linux-systemd.sh"
    _setup_sandbox
    cat "$_tmpdir/systemd-props"
  ' 2>/dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"ProtectSystem=strict"* ]]
  [[ "$output" == *"ProtectHome=read-only"* ]]
  [[ "$output" != *"AppArmorProfile="* ]]
}
