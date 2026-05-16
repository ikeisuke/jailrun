#!/usr/bin/env bats

# Cycle v0.4.1 / Unit 002 / Issue #86
# CLI-level checks that lib/proxy.py honours the SoT port range:
#   - explicit --port outside [START, END] fails closed (range-out below + above)
#   - default --port 0 binds inside [START, END]
#
# These are behavioural assertions per the Phase 1 logical design
# ("主検証は挙動ベース" — codex design R2 #3). Import-statement greps were
# explicitly removed because they are too tightly coupled to implementation
# details and break on equivalent refactors.

load helpers

setup() {
  _repo_root="$BATS_TEST_DIRNAME/.."
  _proxy="$_repo_root/lib/proxy.py"
  _const="$_repo_root/lib/netns-const.sh"

  # shellcheck disable=SC1090
  . "$_const"
  _range_start="$JAILRUN_PROXY_PORT_RANGE_START"
  _range_end="$JAILRUN_PROXY_PORT_RANGE_END"

  _proxy_pid=""
}

teardown() {
  if [ -n "$_proxy_pid" ] && kill -0 "$_proxy_pid" 2>/dev/null; then
    kill "$_proxy_pid" 2>/dev/null || true
    wait "$_proxy_pid" 2>/dev/null || true
  fi
}

# --- explicit out-of-range port: below the start ---

@test "proxy.py fails closed when --port is below the SoT range with --enforce-port-range" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 required"
  fi
  local below=$((_range_start - 1))
  if [ "$below" -lt 1 ]; then
    skip "SoT range starts at 1; no below-range value to test"
  fi
  run python3 "$_proxy" --allow-domains test.invalid --enforce-port-range --port "$below"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside the configured proxy port range"* ]]
}

# --- explicit out-of-range port: above the end ---

@test "proxy.py fails closed when --port is above the SoT range with --enforce-port-range" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 required"
  fi
  local above=$((_range_end + 1))
  if [ "$above" -gt 65535 ]; then
    skip "SoT range ends at 65535; no above-range value to test"
  fi
  run python3 "$_proxy" --allow-domains test.invalid --enforce-port-range --port "$above"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside the configured proxy port range"* ]]
}

# --- default --port 0 with --enforce-port-range: must land inside [START, END] ---

@test "proxy.py with --enforce-port-range binds inside the SoT range" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 required"
  fi
  local outfile="$BATS_TEST_TMPDIR/proxy.out"
  local errfile="$BATS_TEST_TMPDIR/proxy.err"
  python3 "$_proxy" --allow-domains test.invalid --bind 127.0.0.1 --enforce-port-range \
    >"$outfile" 2>"$errfile" &
  _proxy_pid=$!

  # Wait up to 3s for the first stdout line (= bind port).
  local i
  for i in $(seq 1 30); do
    if [ -s "$outfile" ]; then
      break
    fi
    sleep 0.1
  done
  [ -s "$outfile" ] || { cat "$errfile" >&2; false; }

  local port
  port=$(head -n 1 "$outfile")
  [ "$port" -ge "$_range_start" ]
  [ "$port" -le "$_range_end" ]
}

# --- default --port 0 WITHOUT --enforce-port-range: uses unrestricted OS
# ephemeral pool (regression guard for v0.4.0 behaviour, per PR #89
# pre-merge review) ---

@test "proxy.py without --enforce-port-range uses OS ephemeral pool" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 required"
  fi
  local outfile="$BATS_TEST_TMPDIR/proxy_unrestricted.out"
  local errfile="$BATS_TEST_TMPDIR/proxy_unrestricted.err"
  python3 "$_proxy" --allow-domains test.invalid --bind 127.0.0.1 \
    >"$outfile" 2>"$errfile" &
  _proxy_pid=$!

  local i
  for i in $(seq 1 30); do
    if [ -s "$outfile" ]; then
      break
    fi
    sleep 0.1
  done
  [ -s "$outfile" ] || { cat "$errfile" >&2; false; }

  local port
  port=$(head -n 1 "$outfile")
  # Any port > 0 is fine; the assertion is "the proxy started without
  # being squeezed into 60000..60099" — we accept the OS-chosen port.
  [ "$port" -gt 0 ]
  [ "$port" -le 65535 ]
}
