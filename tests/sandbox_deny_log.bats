#!/usr/bin/env bats

load helpers

@test "_start_deny_log sets _DENY_LOG_PID and _DENY_LOG_FILE on Darwin" {
  if [ "$(uname)" != "Darwin" ]; then
    skip "Darwin-only test"
  fi
  setup_jailrun_env
  _tmpdir=$(mktemp -d)
  _WRAPPER_NAME=jailrun

  . "$JAILRUN_LIB/platform/sandbox-darwin.sh"

  _start_deny_log

  [ -n "$_DENY_LOG_PID" ]
  [ -n "$_DENY_LOG_FILE" ]
  [ -f "$_DENY_LOG_FILE" ]

  # Clean up
  _stop_deny_log
  rm -rf "$_tmpdir"
}

@test "_stop_deny_log clears _DENY_LOG_PID but preserves _DENY_LOG_FILE" {
  if [ "$(uname)" != "Darwin" ]; then
    skip "Darwin-only test"
  fi
  setup_jailrun_env
  _tmpdir=$(mktemp -d)
  _WRAPPER_NAME=jailrun

  . "$JAILRUN_LIB/platform/sandbox-darwin.sh"

  _start_deny_log
  _saved_file="$_DENY_LOG_FILE"
  _stop_deny_log

  [ -z "$_DENY_LOG_PID" ]
  [ "$_DENY_LOG_FILE" = "$_saved_file" ]

  rm -rf "$_tmpdir"
}

@test "_stop_deny_log is safe to call when no log is running" {
  if [ "$(uname)" != "Darwin" ]; then
    skip "Darwin-only test"
  fi
  setup_jailrun_env

  . "$JAILRUN_LIB/platform/sandbox-darwin.sh"

  _DENY_LOG_PID=""
  _DENY_LOG_FILE=""
  run _stop_deny_log
  [ "$status" -eq 0 ]
}

@test "sandbox-linux.sh defines no-op _start_deny_log and _stop_deny_log" {
  if [ "$(uname)" = "Darwin" ]; then
    # On macOS, verify that the no-op definitions exist in the file
    run grep -c '_start_deny_log\|_stop_deny_log' "$BATS_TEST_DIRNAME/../lib/platform/sandbox-linux.sh"
    [ "$output" -ge 2 ]
  else
    setup_jailrun_env
    _tmpdir=$(mktemp -d)
    _WRAPPER_NAME=jailrun

    . "$JAILRUN_LIB/platform/sandbox-linux.sh"

    _DENY_LOG_PID=""
    _DENY_LOG_FILE=""
    _start_deny_log
    [ -z "$_DENY_LOG_PID" ]

    rm -rf "$_tmpdir"
  fi
}
