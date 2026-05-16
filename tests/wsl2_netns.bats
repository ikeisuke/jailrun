#!/usr/bin/env bats

# Cycle v0.4.0 / Unit 001 / Issue #84
# Tests for the WSL2 network namespace setup/teardown completeness:
#   - host IP / netns identifiers single source of truth (lib/netns-const.sh)
#   - namespace INPUT direction least-privilege restriction
#   - idempotent teardown script (scripts/wsl2-netns-teardown.sh)
#
# Static/structural tests and non-root error paths run everywhere.
# Behavioural tests that need a real network namespace are gated behind
# _netns_gate_or_skip (skipped when not root / no iproute2 — run them with
# `sudo bats tests/wsl2_netns.bats` on a Linux / WSL2 host).

load helpers

setup() {
  _repo_root="$BATS_TEST_DIRNAME/.."
  _setup="$_repo_root/scripts/wsl2-netns-setup.sh"
  _teardown="$_repo_root/scripts/wsl2-netns-teardown.sh"
  _const="$_repo_root/lib/netns-const.sh"

  # Behavioural tests derive identifiers from the SoT so they track topology
  # changes instead of going stale. Static tests below keep their literals on
  # purpose — those literals are the assertion target.
  # shellcheck disable=SC1090
  . "$_const"
  _ns="$JAILRUN_NETNS_NAME"
  _host_ip="$JAILRUN_NETNS_HOST_IP"
  _veth_host="$JAILRUN_NETNS_VETH_HOST"
  _veth_agent="$JAILRUN_NETNS_VETH_AGENT"
  # agent_ip is intentionally not in the SoT (setup.sh local, see DR-C003);
  # defined once here so behavioural tests reuse it instead of re-hardcoding.
  _agent_ip="10.200.0.2"
}

# Gate behavioural netns tests: need root + iproute2. Skip otherwise so the
# suite stays green on unprivileged CI (a dedicated privileged test env is
# explicitly out of scope for this cycle).
_netns_gate_or_skip() {
  if [ "$(id -u)" -ne 0 ]; then
    skip "root required for netns behaviour tests (run with sudo)"
  fi
  if ! command -v ip >/dev/null 2>&1; then
    skip "ip (iproute2) required for netns behaviour tests"
  fi
}

# --- lib/netns-const.sh: single source of truth ---

@test "netns-const.sh defines all four topology variables" {
  run sh -c '. "'"$_const"'" && printf "%s|%s|%s|%s" \
    "$JAILRUN_NETNS_HOST_IP" "$JAILRUN_NETNS_NAME" \
    "$JAILRUN_NETNS_VETH_HOST" "$JAILRUN_NETNS_VETH_AGENT"'
  [ "$status" -eq 0 ]
  [ "$output" = "10.200.0.1|agentns|veth-host|veth-agent" ]
}

@test "netns-const.sh is POSIX sh clean and has no side effects" {
  run sh -n "$_const"
  [ "$status" -eq 0 ]
  # Sourcing must not print anything (variable assignments only).
  run sh -c '. "'"$_const"'"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- setup.sh references the SoT, no independent hardcoding ---

@test "wsl2-netns-setup.sh sources netns-const.sh" {
  run grep -q 'netns-const.sh' "$_setup"
  [ "$status" -eq 0 ]
}

@test "wsl2-netns-setup.sh no longer hardcodes the netns topology" {
  ! grep -qE '^HOST_IP="10\.200\.0\.1"' "$_setup"
  ! grep -qE '^NS="agentns"' "$_setup"
  ! grep -qE '^VETH_HOST="veth-host"' "$_setup"
  ! grep -qE '^VETH_AGENT="veth-agent"' "$_setup"
}

@test "wsl2-netns-setup.sh assigns its locals from the SoT variables" {
  grep -qE '^NS="\$JAILRUN_NETNS_NAME"' "$_setup"
  grep -qE '^HOST_IP="\$JAILRUN_NETNS_HOST_IP"' "$_setup"
}

# --- sandbox.sh references the SoT, no independent hardcoding ---

@test "sandbox.sh sources netns-const.sh" {
  run grep -q 'netns-const.sh' "$_repo_root/lib/sandbox.sh"
  [ "$status" -eq 0 ]
}

@test "sandbox.sh no longer hardcodes the host IP or namespace name" {
  ! grep -qE '_proxy_bind="10\.200\.0\.1"' "$_repo_root/lib/sandbox.sh"
  ! grep -qE 'grep -qw agentns' "$_repo_root/lib/sandbox.sh"
}

@test "sandbox.sh uses the SoT variables for bind and detection" {
  grep -qE '_proxy_bind="\$JAILRUN_NETNS_HOST_IP"' "$_repo_root/lib/sandbox.sh"
  grep -qE 'grep -qw "\$JAILRUN_NETNS_NAME"' "$_repo_root/lib/sandbox.sh"
}

# --- INPUT direction least-privilege rules present in setup.sh ---

@test "wsl2-netns-setup.sh adds INPUT default-DROP policy" {
  grep -qE 'iptables -P INPUT DROP' "$_setup"
  grep -qE 'iptables -F INPUT' "$_setup"
}

@test "wsl2-netns-setup.sh allows loopback and established/related on INPUT" {
  grep -qE 'iptables -A INPUT -i lo -j ACCEPT' "$_setup"
  grep -qE 'iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT' "$_setup"
}

# --- scripts pass syntax check ---

@test "wsl2-netns-setup.sh and wsl2-netns-teardown.sh pass bash -n" {
  run bash -n "$_setup"
  [ "$status" -eq 0 ]
  run bash -n "$_teardown"
  [ "$status" -eq 0 ]
}

# --- make install distributes netns-const.sh ---

@test "make install distributes lib/netns-const.sh" {
  _prefix="$(mktemp -d)"
  run make -C "$_repo_root" install PREFIX="$_prefix"
  [ "$status" -eq 0 ]
  [ -f "$_prefix/lib/jailrun/netns-const.sh" ]
  rm -rf "$_prefix"
}

# Cycle v0.4.1 / Unit 002: lib/proxy.py now imports netns_const_loader at
# launch, so the install payload must ship the loader alongside proxy.py
# (regression guard for the PR pre-merge review finding in v0.4.1 #89).
@test "make install distributes lib/netns_const_loader.py" {
  _prefix="$(mktemp -d)"
  run make -C "$_repo_root" install PREFIX="$_prefix"
  [ "$status" -eq 0 ]
  [ -f "$_prefix/lib/jailrun/netns_const_loader.py" ]
  rm -rf "$_prefix"
}

# --- teardown script: non-root error path (runs everywhere) ---

@test "wsl2-netns-teardown.sh is executable" {
  [ -x "$_teardown" ]
}

@test "wsl2-netns-teardown.sh refuses to run as non-root" {
  if [ "$(id -u)" -eq 0 ]; then
    skip "this test verifies the non-root rejection path"
  fi
  run "$_teardown"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be run as root"* ]]
}

# --- teardown script: missing SoT error path (root-gated) ---

@test "wsl2-netns-teardown.sh fails clearly when netns-const.sh is missing" {
  _netns_gate_or_skip
  # Copy the script to a temp location with no sibling ../lib/netns-const.sh.
  mkdir -p "$BATS_TEST_TMPDIR/scripts" "$BATS_TEST_TMPDIR/lib"
  cp "$_teardown" "$BATS_TEST_TMPDIR/scripts/wsl2-netns-teardown.sh"
  run "$BATS_TEST_TMPDIR/scripts/wsl2-netns-teardown.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"netns constants not found"* ]]
}

# --- teardown idempotency (root-gated behaviour) ---

@test "wsl2-netns-teardown.sh exits 0 when nothing exists" {
  _netns_gate_or_skip
  # Ensure a clean slate first.
  ip netns del "$_ns" 2>/dev/null || true
  ip link del "$_veth_host" 2>/dev/null || true
  run "$_teardown"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not found, skipping"* ]]
}

@test "wsl2-netns-teardown.sh removes a namespace created by setup, and is repeatable" {
  _netns_gate_or_skip
  command -v iptables >/dev/null 2>&1 || skip "iptables required"
  run "$_setup"
  [ "$status" -eq 0 ]
  ip netns list | grep -qw "$_ns"
  # First teardown removes it.
  run "$_teardown"
  [ "$status" -eq 0 ]
  ! ip netns list | grep -qw "$_ns"
  ! ip link show "$_veth_host" >/dev/null 2>&1
  # Second teardown is a no-op and still exits 0 (idempotent).
  run "$_teardown"
  [ "$status" -eq 0 ]
}

@test "wsl2-netns-teardown.sh cleans up partial residue (veth-host without namespace)" {
  _netns_gate_or_skip
  ip netns del "$_ns" 2>/dev/null || true
  ip link del "$_veth_host" 2>/dev/null || true
  # Simulate a setup that failed after creating the veth pair.
  ip link add "$_veth_host" type veth peer name "$_veth_agent"
  run "$_teardown"
  [ "$status" -eq 0 ]
  ! ip link show "$_veth_host" >/dev/null 2>&1
}

# --- INPUT direction behaviour (root-gated) ---

@test "setup applies INPUT default-DROP inside the namespace" {
  _netns_gate_or_skip
  command -v iptables >/dev/null 2>&1 || skip "iptables required"
  run "$_setup"
  [ "$status" -eq 0 ]
  run ip netns exec "$_ns" iptables -S INPUT
  [ "$status" -eq 0 ]
  [[ "$output" == *"-P INPUT DROP"* ]]
  [[ "$output" == *"-A INPUT -i lo -j ACCEPT"* ]]
  [[ "$output" == *"ESTABLISHED,RELATED -j ACCEPT"* ]]
  "$_teardown"
}

@test "namespace INPUT DROP blocks unrelated host-initiated connections to the agent" {
  _netns_gate_or_skip
  command -v iptables >/dev/null 2>&1 || skip "iptables required"
  run "$_setup"
  [ "$status" -eq 0 ]
  # A new inbound connection from the host to an arbitrary agent port has no
  # matching ESTABLISHED/RELATED state, so the SYN is dropped (not refused):
  # the connect attempt times out rather than failing fast.
  run timeout 3 bash -c 'exec 3<>/dev/tcp/'"$_agent_ip"'/9999'
  [ "$status" -ne 0 ]
  [ "$status" -eq 124 ]
  "$_teardown"
}
