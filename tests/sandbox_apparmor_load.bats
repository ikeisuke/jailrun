#!/usr/bin/env bats

# Cycle v0.3.6 / Unit 001 / Issue #78
#
# Verifies the failure-classification logic of _load_apparmor_profile in
# lib/platform/sandbox-linux-apparmor.sh. The function classifies failures
# into 3 reasons via exit-code-primary signals:
#
#   - unavailable      : apparmor_parser is not on PATH, OR sudo+apparmor_parser
#                        fails with stderr that does NOT start with "apparmor_parser:"
#   - sudo_unavailable : `sudo -n true` fails (no passwordless sudo)
#   - parse_error      : sudo+apparmor_parser fails with stderr starting with
#                        "apparmor_parser:" (locale-independent program-name prefix)
#
# Tests use PATH-prepended fake shims for `sudo` and `apparmor_parser` so they
# run on macOS and Linux without requiring real AppArmor or sudo access.

load helpers

setup() {
  setup_jailrun_env
  _tmpdir=$(mktemp -d)
  export _tmpdir
  _shim_bin="$_tmpdir/shim-bin"
  mkdir -p "$_shim_bin"

  # The function looks for these variables; create a minimal profile file.
  printf 'stub profile\n' > "$_tmpdir/apparmor-profile"
  export _WRAPPER_NAME="claude"
}

teardown() {
  rm -rf "$_tmpdir"
}

# Run _load_apparmor_profile in an isolated subshell, capturing exit code,
# stdout, and stderr separately. The fake shim directory is prepended to PATH.
_run_load() {
  _stderr_file="$_tmpdir/load-stderr"
  set +e
  output=$(
    PATH="$_shim_bin:/usr/bin:/bin" \
    _tmpdir="$_tmpdir" \
    _WRAPPER_NAME="$_WRAPPER_NAME" \
    sh -c '
      . "'"$JAILRUN_LIB"'/platform/sandbox-linux-apparmor.sh"
      _load_apparmor_profile
      echo "[exit:$?]"
    ' 2>"$_stderr_file"
  )
  status=$?
  stderr="$(cat "$_stderr_file")"
  set -e
}

_write_shim() {
  local _name="$1" _body="$2"
  cat > "$_shim_bin/$_name" <<SHIM
#!/bin/sh
$_body
SHIM
  chmod +x "$_shim_bin/$_name"
}

# --- Classification: unavailable ---

@test "_load_apparmor_profile classifies missing apparmor_parser as unavailable" {
  # No apparmor_parser shim → command -v fails → unavailable.
  _write_shim "sudo" 'exit 0'
  _run_load
  [[ "$output" == *"[exit:1]"* ]]
  [[ "$stderr" == *"(reason: unavailable)"* ]]
}

# --- Classification: sudo_unavailable ---

@test "_load_apparmor_profile classifies sudo -n failure as sudo_unavailable" {
  # apparmor_parser exists; sudo -n true fails (exit 1).
  _write_shim "apparmor_parser" 'exit 0'
  _write_shim "sudo" 'exit 1'
  _run_load
  [[ "$output" == *"[exit:1]"* ]]
  [[ "$stderr" == *"(reason: sudo_unavailable)"* ]]
}

# --- Classification: parse_error ---

@test "_load_apparmor_profile classifies apparmor_parser: stderr as parse_error" {
  # sudo -n true succeeds (no args).
  # sudo -n apparmor_parser -r ... fails (with apparmor_parser:-prefixed stderr).
  _write_shim "apparmor_parser" 'echo "apparmor_parser: syntax error at line 1" >&2; exit 1'
  _write_shim "sudo" '
case "$1" in
  -n)
    shift
    if [ "$1" = "true" ]; then exit 0; fi
    # Forward to real-ish exec of the next argument (use shim path).
    "$@"
    ;;
  *)
    exit 1
    ;;
esac
'
  _run_load
  [[ "$output" == *"[exit:1]"* ]]
  [[ "$stderr" == *"(reason: parse_error)"* ]]
  # stderr transparency: raw apparmor_parser message is forwarded.
  [[ "$stderr" == *"apparmor_parser: syntax error at line 1"* ]]
}

# --- Classification: unavailable (parser runs but stderr lacks expected prefix) ---

@test "_load_apparmor_profile classifies generic apparmor_parser failure as unavailable" {
  # Parser fails without apparmor_parser:-prefixed stderr (unexpected failure).
  _write_shim "apparmor_parser" 'echo "kernel module missing" >&2; exit 2'
  _write_shim "sudo" '
case "$1" in
  -n)
    shift
    if [ "$1" = "true" ]; then exit 0; fi
    "$@"
    ;;
  *)
    exit 1
    ;;
esac
'
  _run_load
  [[ "$output" == *"[exit:1]"* ]]
  [[ "$stderr" == *"(reason: unavailable)"* ]]
  [[ "$stderr" == *"kernel module missing"* ]]
}

# --- Success ---

@test "_load_apparmor_profile returns success when sudo and apparmor_parser succeed" {
  _write_shim "apparmor_parser" 'exit 0'
  _write_shim "sudo" '
case "$1" in
  -n)
    shift
    if [ "$1" = "true" ]; then exit 0; fi
    "$@"
    ;;
  *)
    exit 1
    ;;
esac
'
  _run_load
  [[ "$output" == *"[exit:0]"* ]]
  [[ "$stderr" != *"(reason:"* ]]
}
