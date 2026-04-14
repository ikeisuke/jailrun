#!/bin/sh
# KC-01: Seatbelt keychain-access-* operation investigation
# Tests whether Seatbelt can deny keychain-access-* operations.
#
# Output: structured scenario results (one per line)
# Format: scenario_id:verdict:confidence:error_kind:evidence_summary
#
# Exit: 0=normal completion, 1=environment error

set -e

# --- Environment check ---
if ! command -v sandbox-exec >/dev/null 2>&1; then
  echo "KC-01-S0:inconclusive:high:env_error:sandbox-exec not found" >&2
  exit 1
fi

_tmpdir=$(mktemp -d)
trap 'rm -rf "$_tmpdir"' EXIT

_log_file="$_tmpdir/deny.log"

# Helper: run a command inside a Seatbelt sandbox with given profile rules
# and capture deny log output
_run_sandboxed() {
  local _scenario_id="$1"
  local _extra_rules="$2"
  shift 2

  local _sb="$_tmpdir/${_scenario_id}.sb"
  cat > "$_sb" <<SBEOF
(version 1)
(allow default)
${_extra_rules}
SBEOF

  # Start log stream for deny events (background)
  : > "$_log_file"
  log stream --style ndjson \
    --predicate 'subsystem == "com.apple.sandbox" AND eventMessage CONTAINS "deny"' \
    > "$_log_file" 2>/dev/null &
  local _log_pid=$!
  sleep 0.5  # allow log stream to attach

  # Run the test command
  local _exit_code=0
  local _stderr_file="$_tmpdir/${_scenario_id}.stderr"
  sandbox-exec -f "$_sb" "$@" > /dev/null 2>"$_stderr_file" || _exit_code=$?

  sleep 0.5  # allow log to flush
  kill "$_log_pid" 2>/dev/null || true
  wait "$_log_pid" 2>/dev/null || true

  # Collect evidence
  local _deny_count=0
  _deny_count=$(grep -c "deny" "$_log_file" 2>/dev/null) || _deny_count=0
  local _stderr_summary
  _stderr_summary=$(head -1 "$_stderr_file" 2>/dev/null | tr ':' '=' | head -c 200)

  echo "${_exit_code}:${_deny_count}:${_stderr_summary}"
}

# --- KC-01-S1: deny keychain-access-read-item ---
echo "=== KC-01-S1: keychain-access-read-item ===" >&2
_result=$(_run_sandboxed "KC-01-S1" \
  '(deny keychain-access-read-item)' \
  security find-generic-password -s "jailrun-test-nonexistent" 2>&1) || true

_exit=$(echo "$_result" | cut -d: -f1)
_denies=$(echo "$_result" | cut -d: -f2)
_stderr=$(echo "$_result" | cut -d: -f3-)

if [ "$_exit" = "65" ]; then
  echo "KC-01-S1:not_controllable:high:none:profile parse error (exit=65, unbound variable) stderr=${_stderr}"
elif [ "$_denies" -gt 0 ] 2>/dev/null; then
  echo "KC-01-S1:controllable:high:none:deny log captured ${_denies} events"
elif [ "$_exit" != "0" ]; then
  echo "KC-01-S1:inconclusive:medium:none:command failed (exit=${_exit}) stderr=${_stderr}"
else
  echo "KC-01-S1:not_controllable:high:none:no deny events, exit=0"
fi

# --- KC-01-S2: deny keychain-access-modify-item ---
echo "=== KC-01-S2: keychain-access-modify-item ===" >&2
_result=$(_run_sandboxed "KC-01-S2" \
  '(deny keychain-access-modify-item)' \
  security add-generic-password -s "jailrun-test-tmp" -a "test" -w "test" -T "" 2>&1) || true

_exit=$(echo "$_result" | cut -d: -f1)
_denies=$(echo "$_result" | cut -d: -f2)
_stderr=$(echo "$_result" | cut -d: -f3-)

if [ "$_exit" = "65" ]; then
  echo "KC-01-S2:not_controllable:high:none:profile parse error (exit=65) stderr=${_stderr}"
elif [ "$_denies" -gt 0 ] 2>/dev/null; then
  echo "KC-01-S2:controllable:high:none:deny log captured ${_denies} events"
elif [ "$_exit" != "0" ]; then
  echo "KC-01-S2:inconclusive:medium:none:command failed (exit=${_exit}) stderr=${_stderr}"
else
  echo "KC-01-S2:not_controllable:high:none:no deny events, exit=0"
fi
# Cleanup test item if created
security delete-generic-password -s "jailrun-test-tmp" -a "test" 2>/dev/null || true

# --- KC-01-S3: deny keychain-access-add-item ---
echo "=== KC-01-S3: keychain-access-add-item ===" >&2
_result=$(_run_sandboxed "KC-01-S3" \
  '(deny keychain-access-add-item)' \
  security add-generic-password -s "jailrun-test-tmp2" -a "test" -w "test" -T "" 2>&1) || true

_exit=$(echo "$_result" | cut -d: -f1)
_denies=$(echo "$_result" | cut -d: -f2)
_stderr=$(echo "$_result" | cut -d: -f3-)

if [ "$_exit" = "65" ]; then
  echo "KC-01-S3:not_controllable:high:none:profile parse error (exit=65) stderr=${_stderr}"
elif [ "$_denies" -gt 0 ] 2>/dev/null; then
  echo "KC-01-S3:controllable:high:none:deny log captured ${_denies} events"
elif [ "$_exit" != "0" ]; then
  echo "KC-01-S3:inconclusive:medium:none:command failed (exit=${_exit}) stderr=${_stderr}"
else
  echo "KC-01-S3:not_controllable:high:none:no deny events, exit=0"
fi
security delete-generic-password -s "jailrun-test-tmp2" -a "test" 2>/dev/null || true

# --- KC-01-S4: deny keychain-access-acl-change ---
echo "=== KC-01-S4: keychain-access-acl-change ===" >&2
# ACL change is hard to trigger directly; we test the profile acceptance
_sb_test="$_tmpdir/KC-01-S4.sb"
cat > "$_sb_test" <<'SBEOF'
(version 1)
(allow default)
(deny keychain-access-acl-change)
SBEOF

if sandbox-exec -f "$_sb_test" /usr/bin/true 2>/dev/null; then
  echo "KC-01-S4:partial:low:none:profile accepted but no practical trigger available"
else
  echo "KC-01-S4:inconclusive:low:none:profile rejected by sandbox-exec"
fi

# --- KC-01-S5: keychain-access-* with filter ---
echo "=== KC-01-S5: filter support ===" >&2
# Test if keychain-access-* supports filter expressions (like file operations do)
_sb_filter="$_tmpdir/KC-01-S5.sb"
cat > "$_sb_filter" <<'SBEOF'
(version 1)
(allow default)
(deny keychain-access-read-item
  (keychain-item-class "genp"))
SBEOF

_filter_result="inconclusive"
_filter_evidence=""
if sandbox-exec -f "$_sb_filter" /usr/bin/true 2>"$_tmpdir/KC-01-S5.stderr"; then
  _filter_result="controllable"
  _filter_evidence="profile with filter accepted"
else
  _filter_stderr=$(head -1 "$_tmpdir/KC-01-S5.stderr" | tr ':' '=' | head -c 200)
  _filter_result="not_controllable"
  _filter_evidence="profile rejected=${_filter_stderr}"
fi
echo "KC-01-S5:${_filter_result}:medium:none:${_filter_evidence}"
