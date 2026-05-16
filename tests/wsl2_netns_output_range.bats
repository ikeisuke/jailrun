#!/usr/bin/env bats

# Cycle v0.4.1 / Unit 001 / Issue #86
# Tests for the WSL2 network namespace OUTPUT iptables port-range scoping:
#   - lib/netns-const.sh single SoT for JAILRUN_PROXY_PORT_RANGE_{START,END}
#   - scripts/wsl2-netns-setup.sh applies --dport START:END on the OUTPUT
#     ACCEPT rule, validates the SoT range on the consumer side and stays
#     idempotent across re-setup runs.
#
# Static / structural tests run everywhere. Behavioural tests that need a
# real network namespace (root + iptables + iproute2 + a listener on the
# host side) are gated behind _netns_gate_or_skip and the iptables /
# python3 availability checks — they are skipped on unprivileged CI and
# only run with `sudo bats tests/wsl2_netns_output_range.bats` on a
# Linux / WSL2 host (matching the existing tests/wsl2_netns.bats pattern).

load helpers

setup() {
  _repo_root="$BATS_TEST_DIRNAME/.."
  _setup="$_repo_root/scripts/wsl2-netns-setup.sh"
  _teardown="$_repo_root/scripts/wsl2-netns-teardown.sh"
  _const="$_repo_root/lib/netns-const.sh"

  # shellcheck disable=SC1090
  . "$_const"
  _ns="$JAILRUN_NETNS_NAME"
  _host_ip="$JAILRUN_NETNS_HOST_IP"
  _range_start="$JAILRUN_PROXY_PORT_RANGE_START"
  _range_end="$JAILRUN_PROXY_PORT_RANGE_END"

  _listener_pid=""
  _listener_log="$BATS_TEST_TMPDIR/listener.log"
}

teardown() {
  if [ -n "$_listener_pid" ] && kill -0 "$_listener_pid" 2>/dev/null; then
    kill "$_listener_pid" 2>/dev/null || true
    wait "$_listener_pid" 2>/dev/null || true
  fi
}

# Gate behavioural netns tests: need root + iproute2 + iptables. Skip
# otherwise so the suite stays green on unprivileged CI.
_netns_gate_or_skip() {
  if [ "$(id -u)" -ne 0 ]; then
    skip "root required for netns behaviour tests (run with sudo)"
  fi
  if ! command -v ip >/dev/null 2>&1; then
    skip "ip (iproute2) required for netns behaviour tests"
  fi
  if ! command -v iptables >/dev/null 2>&1; then
    skip "iptables required for netns behaviour tests"
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 required for the host-side listener helper"
  fi
}

# Start a TCP listener on $_host_ip:<port> via python3 in the background.
# Polls /dev/tcp until accept is ready (max 3 s). Fails the test (not
# skip) when the listener does not come up — required to keep B2's
# timeout signal attributable to the OUTPUT DROP rule (triangulation
# in the logical design: B1 + B2 + B3 must run together).
_start_host_listener() {
  local port="$1"
  python3 - "$_host_ip" "$port" >"$_listener_log" 2>&1 <<'PY' &
import socket, sys, time
host, port = sys.argv[1], int(sys.argv[2])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((host, port))
s.listen(8)
s.settimeout(30)
try:
    conn, _ = s.accept()
    conn.close()
except (socket.timeout, OSError):
    pass
finally:
    s.close()
PY
  _listener_pid=$!

  # Wait until the listener accepts a probing connect (max 3 s).
  local i
  for i in $(seq 1 30); do
    if (exec 3<>"/dev/tcp/$_host_ip/$port") 2>/dev/null; then
      exec 3<&-
      exec 3>&-
      return 0
    fi
    sleep 0.1
  done
  echo "listener did not become ready on $_host_ip:$port within 3s" >&2
  cat "$_listener_log" >&2 || true
  return 1
}

# --- S1: SoT defines port range variables ---

@test "netns-const.sh defines port range variables" {
  run sh -c '. "'"$_const"'" && printf "%s|%s" \
    "$JAILRUN_PROXY_PORT_RANGE_START" "$JAILRUN_PROXY_PORT_RANGE_END"'
  [ "$status" -eq 0 ]
  [ "$output" = "60000|60099" ]
}

# --- S2: netns-const.sh stays side-effect free with the new variables ---

@test "netns-const.sh remains POSIX sh clean with port range additions" {
  run sh -n "$_const"
  [ "$status" -eq 0 ]
  run sh -c '. "'"$_const"'"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- S3: setup.sh OUTPUT rule has the --dport constraint ---

@test "wsl2-netns-setup.sh OUTPUT rule has --dport range constraint" {
  grep -qE '\-A OUTPUT -p tcp -d "\$HOST_IP" \\' "$_setup"
  grep -qE -- '--dport "\$PORT_RANGE_START":"\$PORT_RANGE_END" -j ACCEPT' "$_setup"
}

# --- S4: setup.sh validates the SoT range on the consumer side ---

@test "wsl2-netns-setup.sh validates the SoT port range" {
  grep -qE 'JAILRUN_PROXY_PORT_RANGE_START / _END must be integers in 1\.\.65535' "$_setup"
  # Range incompleteness path reuses the existing "constants incomplete" message.
  grep -cE 'netns constants incomplete in \$NETNS_CONST' "$_setup" >/dev/null
}

# --- S5: setup.sh still passes bash -n after the changes ---

@test "wsl2-netns-setup.sh passes bash -n with the new logic" {
  run bash -n "$_setup"
  [ "$status" -eq 0 ]
}

# --- S6: SoT values satisfy the invariants ---

@test "port range satisfies invariants (1 <= START <= END <= 65535)" {
  [ "$_range_start" -ge 1 ]
  [ "$_range_end" -le 65535 ]
  [ "$_range_start" -le "$_range_end" ]
}

# --- S7: setup.sh exits cleanly when the SoT port range is invalid ---

@test "wsl2-netns-setup.sh rejects a non-integer port range" {
  # Run via env override + a stub root check is impossible without sudo —
  # so instead exercise the validation path via a controlled re-exec of
  # the validation block. We copy the script and stub `id` to simulate
  # root, then point NETNS_CONST at a fixture that injects bad values.
  if [ "$(id -u)" -eq 0 ]; then
    skip "running as root would proceed past validation into real netns ops"
  fi

  local fixture="$BATS_TEST_TMPDIR/scripts"
  local fixture_lib="$BATS_TEST_TMPDIR/lib"
  mkdir -p "$fixture" "$fixture_lib"
  cp "$_setup" "$fixture/wsl2-netns-setup.sh"
  # Stub id => 0 by prepending a wrapper to PATH.
  local shim_bin="$BATS_TEST_TMPDIR/shim-bin"
  mkdir -p "$shim_bin"
  cat >"$shim_bin/id" <<'EOSH'
#!/bin/sh
[ "$1" = "-u" ] && { printf 0; exit 0; }
exec /usr/bin/env id "$@"
EOSH
  chmod +x "$shim_bin/id"

  # Iterate the shared test vectors (tests/port_range_invalid_vectors.py) —
  # this is the same data the Python loader unit tests consume, so any
  # divergence between setup.sh and lib/netns_const_loader.py is caught
  # by both suites pointing at the same fixture set (cycle v0.4.1 / Unit 002
  # logical design, codex plan R1 #4 + design R2 #2).
  local vectors_script="$_repo_root/tests"
  local vectors
  vectors=$(python3 -c "
import sys
sys.path.insert(0, '$vectors_script')
from port_range_invalid_vectors import INVALID_VECTORS
for v in INVALID_VECTORS:
    print('\t'.join(v))
")
  [ -n "$vectors" ]

  local line
  while IFS=$'\t' read -r raw_start raw_end label; do
    cat >"$fixture_lib/netns-const.sh" <<EOC
JAILRUN_NETNS_HOST_IP="10.200.0.1"
JAILRUN_NETNS_NAME="agentns"
JAILRUN_NETNS_VETH_HOST="veth-host"
JAILRUN_NETNS_VETH_AGENT="veth-agent"
JAILRUN_PROXY_PORT_RANGE_START="${raw_start}"
JAILRUN_PROXY_PORT_RANGE_END="${raw_end}"
EOC
    PATH="$shim_bin:$PATH" run "$fixture/wsl2-netns-setup.sh"
    if [ "$status" -eq 0 ]; then
      echo "vector ${label} (${raw_start},${raw_end}) was accepted; expected exit 1" >&2
      false
    fi
    if ! [[ "$output" == *"netns constants incomplete in"* \
         || "$output" == *"must be integers in 1..65535"* ]]; then
      echo "vector ${label} (${raw_start},${raw_end}) exit 1 but wrong message: $output" >&2
      false
    fi
  done <<< "$vectors"
}

# --- B1: setup applies OUTPUT --dport range inside the namespace ---

@test "setup applies OUTPUT --dport range inside the namespace" {
  _netns_gate_or_skip
  run "$_setup"
  [ "$status" -eq 0 ]
  run ip netns exec "$_ns" iptables -S OUTPUT
  [ "$status" -eq 0 ]
  [[ "$output" == *"-P OUTPUT DROP"* ]]
  [[ "$output" == *"-A OUTPUT -o lo -j ACCEPT"* ]]
  [[ "$output" == *"--dport ${_range_start}:${_range_end}"* ]]
  [[ "$output" == *"-d ${_host_ip}"* ]]
  "$_teardown"
}

# --- B2: a destination port outside the range is dropped (triangulated
# with B1 + B3 per the design "決定性の根拠" section) ---

@test "namespace egress to a port outside the SoT range is dropped" {
  _netns_gate_or_skip
  if [ "$_range_start" -le 8080 ] && [ 8080 -le "$_range_end" ]; then
    skip "port 8080 falls inside the configured SoT range, cannot probe deny path"
  fi
  run "$_setup"
  [ "$status" -eq 0 ]
  _start_host_listener 8080
  # OUTPUT DROP swallows the SYN, so the in-namespace connect times out
  # rather than being refused fast. status=124 is the GNU `timeout` rc.
  run ip netns exec "$_ns" timeout 3 bash -c 'exec 3<>/dev/tcp/'"$_host_ip"'/8080'
  [ "$status" -eq 124 ]
  "$_teardown"
}

# --- B3: a destination port inside the range is accepted (proves the
# listener / route are healthy, ruling out B2 false-positives) ---

@test "namespace egress to a port inside the SoT range is accepted" {
  _netns_gate_or_skip
  local in_port="$_range_start"
  run "$_setup"
  [ "$status" -eq 0 ]
  _start_host_listener "$in_port"
  run ip netns exec "$_ns" timeout 3 bash -c "exec 3<>/dev/tcp/$_host_ip/$in_port"
  [ "$status" -eq 0 ]
  "$_teardown"
}

# --- B4: re-setup is idempotent for the OUTPUT --dport ACCEPT row ---

@test "re-setup is idempotent for the OUTPUT --dport ACCEPT row" {
  _netns_gate_or_skip
  run "$_setup"
  [ "$status" -eq 0 ]
  run "$_setup"
  [ "$status" -eq 0 ]
  run ip netns exec "$_ns" iptables -S OUTPUT
  [ "$status" -eq 0 ]
  # Exactly one --dport ACCEPT row, regardless of how many times setup ran.
  local count
  count=$(printf '%s\n' "$output" | grep -cE -- "--dport ${_range_start}:${_range_end}.*-j ACCEPT" || true)
  [ "$count" -eq 1 ]
  "$_teardown"
}
