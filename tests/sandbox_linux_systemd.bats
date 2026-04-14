#!/usr/bin/env bats

# Tests for lib/platform/sandbox-linux-systemd.sh
# Verifies property file generation without requiring actual systemd-run.

load helpers

setup() {
  setup_jailrun_env
  _tmpdir=$(mktemp -d)
  export _tmpdir

  # Stub _detect_git_worktree (not testing git integration here)
  _detect_git_worktree() { :; }
  export -f _detect_git_worktree 2>/dev/null || true

  # Default empty values for optional variables
  _git_parent_toplevel=""
  _git_common_dir=""
  _other_worktrees=""
  _SANDBOX_ALLOW_WRITE_PATHS=""
  _SANDBOX_DENY_READ_PATHS=""
  _WRAPPER_NAME="claude"
}

teardown() {
  rm -rf "$_tmpdir"
}

# Helper: source the script and run _setup_sandbox, then cat the props file
run_setup_sandbox() {
  run sh -c '
    _tmpdir="'"$_tmpdir"'"
    _git_parent_toplevel="'"${_git_parent_toplevel:-}"'"
    _git_common_dir="'"${_git_common_dir:-}"'"
    _other_worktrees="'"${_other_worktrees:-}"'"
    _SANDBOX_ALLOW_WRITE_PATHS="'"${_SANDBOX_ALLOW_WRITE_PATHS:-}"'"
    _SANDBOX_DENY_READ_PATHS="'"${_SANDBOX_DENY_READ_PATHS:-}"'"
    _WRAPPER_NAME="claude"
    export PROXY_ENABLED="'"${PROXY_ENABLED:-false}"'"
    _detect_git_worktree() { :; }
    . "'"$JAILRUN_LIB"'/platform/sandbox-linux-systemd.sh"
    _setup_sandbox
    cat "$_tmpdir/systemd-props"
  '
}

# --- Basic property generation ---

@test "generates NoNewPrivileges property" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"NoNewPrivileges=yes"* ]]
}

@test "generates CapabilityBoundingSet empty" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"CapabilityBoundingSet="* ]]
}

@test "generates RestrictSUIDSGID property" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"RestrictSUIDSGID=yes"* ]]
}

@test "generates LockPersonality property" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"LockPersonality=yes"* ]]
}

@test "generates ProtectSystem=strict" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"ProtectSystem=strict"* ]]
}

@test "generates ProtectHome=read-only" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"ProtectHome=read-only"* ]]
}

@test "generates SystemCallFilter" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"SystemCallFilter=@system-service"* ]]
  [[ "$output" == *"SystemCallFilter=~@privileged @debug"* ]]
}

@test "generates device restrictions" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"DevicePolicy=closed"* ]]
  [[ "$output" == *"DeviceAllow=/dev/null rw"* ]]
  [[ "$output" == *"DeviceAllow=/dev/random r"* ]]
  [[ "$output" == *"DeviceAllow=/dev/urandom r"* ]]
}

@test "generates kernel protection properties" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"ProtectProc=invisible"* ]]
  [[ "$output" == *"ProtectClock=yes"* ]]
  [[ "$output" == *"ProtectHostname=yes"* ]]
  [[ "$output" == *"ProtectKernelLogs=yes"* ]]
  [[ "$output" == *"ProtectKernelModules=yes"* ]]
  [[ "$output" == *"ProtectKernelTunables=yes"* ]]
}

# --- PROXY_ENABLED ---

@test "PROXY_ENABLED=true adds IP address restrictions" {
  PROXY_ENABLED=true
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"IPAddressDeny=any"* ]]
  [[ "$output" == *"IPAddressAllow=127.0.0.0/8"* ]]
  [[ "$output" == *"IPAddressAllow=::1/128"* ]]
}

@test "PROXY_ENABLED=1 adds IP address restrictions" {
  PROXY_ENABLED=1
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"IPAddressDeny=any"* ]]
}

@test "PROXY_ENABLED=false does not add IPAddressDeny" {
  PROXY_ENABLED=false
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" != *"IPAddressDeny=any"* ]]
}

@test "PROXY_ENABLED unset does not add IPAddressDeny" {
  unset PROXY_ENABLED
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" != *"IPAddressDeny=any"* ]]
}

# --- Custom paths ---

@test "SANDBOX_ALLOW_WRITE_PATHS adds ReadWritePaths" {
  _write_dir=$(mktemp -d)
  _SANDBOX_ALLOW_WRITE_PATHS="$_write_dir"
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"ReadWritePaths=$_write_dir"* ]]
  rm -rf "$_write_dir"
}

@test "SANDBOX_DENY_READ_PATHS adds InaccessiblePaths for directories" {
  _deny_dir=$(mktemp -d)
  _SANDBOX_DENY_READ_PATHS="$_deny_dir"
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"InaccessiblePaths=$_deny_dir"* ]]
  rm -rf "$_deny_dir"
}

@test "SANDBOX_DENY_READ_PATHS adds InaccessiblePaths for files" {
  _deny_file=$(mktemp)
  _SANDBOX_DENY_READ_PATHS="$_deny_file"
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"InaccessiblePaths=$_deny_file"* ]]
  rm -f "$_deny_file"
}

@test "SANDBOX_DENY_READ_PATHS skips non-existent paths" {
  _SANDBOX_DENY_READ_PATHS="/nonexistent/path/for/testing"
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" != *"InaccessiblePaths=/nonexistent/path/for/testing"* ]]
}

# --- Git worktree ---

@test "git_parent_toplevel adds ReadWritePaths" {
  _wt_dir=$(mktemp -d)
  _git_parent_toplevel="$_wt_dir"
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"ReadWritePaths=$_wt_dir"* ]]
  rm -rf "$_wt_dir"
}

@test "git_common_dir fallback adds ReadWritePaths when no parent_toplevel" {
  _common_dir=$(mktemp -d)
  _git_parent_toplevel=""
  _git_common_dir="$_common_dir"
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"ReadWritePaths=$_common_dir"* ]]
  rm -rf "$_common_dir"
}

# --- ReadWritePaths for cwd and tmpdir ---

@test "includes ReadWritePaths for current directory" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  # PWD should appear as ReadWritePaths
  [[ "$output" == *"ReadWritePaths="* ]]
}

@test "includes ReadWritePaths for tmpdir" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"ReadWritePaths=$_tmpdir"* ]]
}
