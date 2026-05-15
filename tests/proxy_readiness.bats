#!/usr/bin/env bats

# Cycle v0.4.0 / Unit 002 / Issue #83
# Tests for proxy startup hardening in lib/sandbox.sh:
#   sub A — namespace readiness pre-flight verification (fail-closed)
#   sub B — proxy stderr always persisted to $_tmpdir/proxy.log + path notice
#   shared — _proxy_should_start is the single decision point
#
# Strategy: mirror lib/ into a fake JAILRUN_LIB (real sandbox.sh +
# netns-const.sh + platform stubs) and stub the `ip` command via a PATH shim
# so behavioural tests don't need root or a real network namespace.

load helpers

setup() {
  setup_jailrun_env
  _fake_lib="$(mktemp -d)"
  export _fake_lib

  mkdir -p "$_fake_lib/platform" "$_fake_lib/shim-bin"

  # Mirror sandbox.sh and the netns-const.sh SoT it sources.
  cp "$JAILRUN_LIB/sandbox.sh" "$_fake_lib/sandbox.sh"
  cp "$JAILRUN_LIB/netns-const.sh" "$_fake_lib/netns-const.sh"
  printf '#!/bin/sh\n# stub for tests\n' > "$_fake_lib/platform/sandbox-darwin.sh"
  printf '#!/bin/sh\n# stub for tests\n' > "$_fake_lib/platform/sandbox-linux.sh"

  # PATH shim for `ip`. Behaviour driven by IP_SHIM_* env vars set per-test:
  #   IP_SHIM_VETH_EXISTS=1  -> `ip link show veth-host` succeeds
  #   IP_SHIM_HAS_HOST_IP=1  -> `ip -o -4 addr show dev veth-host` prints CIDR line
  cat > "$_fake_lib/shim-bin/ip" <<'SHIM'
#!/bin/sh
case "$1 $2 $3" in
  "link show veth-host")
    [ "${IP_SHIM_VETH_EXISTS:-0}" = "1" ]
    exit $?
    ;;
  "-o -4 addr")
    # remaining args: "show dev veth-host"
    if [ "${IP_SHIM_HAS_HOST_IP:-0}" = "1" ]; then
      echo "5: veth-host    inet 10.200.0.1/24 brd 10.200.0.255 scope global veth-host"
      exit 0
    fi
    exit 0
    ;;
  "netns list ")
    # _NETNS detection — emit nothing by default; tests that want to simulate
    # an active namespace set NS_DETECTED=1 (handled below).
    if [ "${NS_DETECTED:-0}" = "1" ]; then
      echo "agentns"
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
SHIM
  chmod +x "$_fake_lib/shim-bin/ip"

  # PATH shim for `python3`. _start_proxy reads the first stdout line as the
  # bound port, then probes the process with `kill -0`. The shim writes a
  # placeholder port and exits — that's enough to exercise the "proxy log:"
  # announcement path without spawning a real proxy. Tests that need the
  # success branch should not rely on _PROXY_PORT being usable beyond that.
  cat > "$_fake_lib/shim-bin/python3" <<'SHIM'
#!/bin/sh
echo 12345
exit 0
SHIM
  chmod +x "$_fake_lib/shim-bin/python3"

  _fake_home="$(mktemp -d)"
  export _fake_home
  _fake_tmpdir="$(mktemp -d)"
  export _fake_tmpdir
}

teardown() {
  rm -rf "$_fake_lib" "$_fake_home" "$_fake_tmpdir"
}

# Source sandbox.sh in an isolated subshell with the PATH shim for `ip`.
# The `extra` parameter lets a test inject additional shell to evaluate
# after sourcing (e.g. call _verify_proxy_readiness, print a variable).
_run_sandbox() {
  local extra="$1"
  shift
  # Drop `set -eu` here: sandbox.sh references several SANDBOX_EXTRA_* env
  # vars without `:-` defaults, so `set -u` in env -i context trips before
  # we reach the code under test. The launch block uses explicit `exit 1`
  # for fail-closed paths, which works regardless of `set -e`.
  env -i HOME="$_fake_home" \
    JAILRUN_LIB="$_fake_lib" \
    PATH="$_fake_lib/shim-bin:$PATH" \
    "$@" \
    bash -c "
      _tmpdir='$_fake_tmpdir'
      _WRAPPER_NAME=claude
      . '$_fake_lib/sandbox.sh'
      $extra
    "
}

# --- Static structure tests (always run) ---

@test "sandbox.sh defines _proxy_should_start function" {
  run grep -qE '^_proxy_should_start\(\) \{' "$JAILRUN_LIB/sandbox.sh"
  [ "$status" -eq 0 ]
}

@test "sandbox.sh defines _verify_proxy_readiness function" {
  run grep -qE '^_verify_proxy_readiness\(\) \{' "$JAILRUN_LIB/sandbox.sh"
  [ "$status" -eq 0 ]
}

@test "sandbox.sh top-level launch block gates on _NETNS and _proxy_should_start" {
  run grep -qE 'if \[ -n "\$_NETNS" \] && _proxy_should_start; then' "$JAILRUN_LIB/sandbox.sh"
  [ "$status" -eq 0 ]
  run grep -qE '_verify_proxy_readiness \|\| exit 1' "$JAILRUN_LIB/sandbox.sh"
  [ "$status" -eq 0 ]
}

@test "_start_proxy persists proxy stderr to \$_tmpdir/proxy.log unconditionally" {
  # The conditional log-path assignment is gone; only the unconditional one remains.
  ! grep -qE '_proxy_log="/dev/null"' "$JAILRUN_LIB/sandbox.sh"
  ! grep -qE 'AGENT_SANDBOX_DEBUG.*=.*1.*_proxy_log="\$_tmpdir/proxy.log"' "$JAILRUN_LIB/sandbox.sh"
  grep -qE '_proxy_log="\$_tmpdir/proxy.log"' "$JAILRUN_LIB/sandbox.sh"
}

@test "_start_proxy announces the proxy log path on stderr" {
  grep -qE 'echo "\[\$_WRAPPER_NAME\] proxy log: \$_proxy_log"' "$JAILRUN_LIB/sandbox.sh"
}

@test "_start_proxy retains the empty-allow-domains WARN" {
  grep -qE 'WARN: proxy enabled but no proxy_allow_domains' "$JAILRUN_LIB/sandbox.sh"
}

# --- _proxy_should_start behaviour matrix ---

@test "_proxy_should_start: true + non-empty domains -> 0" {
  run _run_sandbox '_proxy_should_start; echo $?' \
    PROXY_ENABLED=true PROXY_ALLOW_DOMAINS=example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"0"* ]]
}

@test "_proxy_should_start: 1 + non-empty domains -> 0" {
  run _run_sandbox '_proxy_should_start; echo $?' \
    PROXY_ENABLED=1 PROXY_ALLOW_DOMAINS=example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"0"* ]]
}

@test "_proxy_should_start: false -> 1" {
  run _run_sandbox '_proxy_should_start; echo $?' \
    PROXY_ENABLED=false PROXY_ALLOW_DOMAINS=example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"1"* ]]
}

@test "_proxy_should_start: enabled but empty domains -> 1" {
  run _run_sandbox '_proxy_should_start; echo $?' \
    PROXY_ENABLED=true PROXY_ALLOW_DOMAINS=
  [ "$status" -eq 0 ]
  [[ "$output" == *"1"* ]]
}

@test "_proxy_should_start: unset PROXY_ENABLED -> 1" {
  run _run_sandbox '_proxy_should_start; echo $?'
  [ "$status" -eq 0 ]
  [[ "$output" == *"1"* ]]
}

# --- _verify_proxy_readiness behaviour matrix (using ip shim) ---

@test "_verify_proxy_readiness: veth-host missing -> return 1 with named-resource error" {
  run _run_sandbox '_verify_proxy_readiness; echo "RC:$?"' IP_SHIM_VETH_EXISTS=0
  [ "$status" -eq 0 ]
  [[ "$output" == *"host veth 'veth-host' is missing"* ]]
  [[ "$output" == *"RC:1"* ]]
}

@test "_verify_proxy_readiness: veth present but host IP not assigned -> return 1" {
  run _run_sandbox '_verify_proxy_readiness; echo "RC:$?"' \
    IP_SHIM_VETH_EXISTS=1 IP_SHIM_HAS_HOST_IP=0
  [ "$status" -eq 0 ]
  [[ "$output" == *"host IP '10.200.0.1' is not assigned"* ]]
  [[ "$output" == *"RC:1"* ]]
}

@test "_verify_proxy_readiness: veth and host IP present -> return 0 silently" {
  run _run_sandbox '_verify_proxy_readiness; echo "RC:$?"' \
    IP_SHIM_VETH_EXISTS=1 IP_SHIM_HAS_HOST_IP=1
  [ "$status" -eq 0 ]
  [[ "$output" == *"RC:0"* ]]
  # Must not emit error/hint when readiness passes.
  [[ "$output" != *"error:"* ]]
  [[ "$output" != *"hint:"* ]]
}

@test "_verify_proxy_readiness: failure messages include the recovery hint" {
  run _run_sandbox '_verify_proxy_readiness; true' IP_SHIM_VETH_EXISTS=0
  [ "$status" -eq 0 ]
  [[ "$output" == *"hint:"* ]]
  [[ "$output" == *"wsl2-netns-setup.sh"* ]]
}

# --- Top-level launch block: regression and Intent M4(a) regression ---

@test "sourcing sandbox.sh with _NETNS empty (no agentns) does not exit" {
  # NS_DETECTED unset -> shim's `ip netns list` prints nothing -> _NETNS=""
  # Even with PROXY_ENABLED=true, the readiness gate must skip and source must succeed.
  run _run_sandbox 'echo "SOURCED:OK"' \
    PROXY_ENABLED=true PROXY_ALLOW_DOMAINS=example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOURCED:OK"* ]]
}

@test "Intent M4(a): PROXY_ENABLED=false skips readiness even when agentns is detected" {
  # Even if the namespace is "detected", _proxy_should_start is false so
  # the readiness gate must not fire and source must succeed.
  run _run_sandbox 'echo "SOURCED:OK"' \
    NS_DETECTED=1 PROXY_ENABLED=false IP_SHIM_VETH_EXISTS=0
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOURCED:OK"* ]]
}

@test "Intent M4(a): unset PROXY_ENABLED skips readiness even when agentns is detected" {
  run _run_sandbox 'echo "SOURCED:OK"' \
    NS_DETECTED=1 IP_SHIM_VETH_EXISTS=0
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOURCED:OK"* ]]
}

@test "agentns detected + proxy will start + readiness fails -> source exits 1 (fail-closed)" {
  run _run_sandbox 'echo "SOURCED:UNREACHABLE"' \
    NS_DETECTED=1 PROXY_ENABLED=true PROXY_ALLOW_DOMAINS=example.com \
    IP_SHIM_VETH_EXISTS=0
  [ "$status" -eq 1 ]
  [[ "$output" != *"SOURCED:UNREACHABLE"* ]]
  [[ "$output" == *"host veth 'veth-host' is missing"* ]]
}

@test "agentns detected + proxy will start + readiness passes -> source succeeds" {
  run _run_sandbox 'echo "SOURCED:OK"' \
    NS_DETECTED=1 PROXY_ENABLED=true PROXY_ALLOW_DOMAINS=example.com \
    IP_SHIM_VETH_EXISTS=1 IP_SHIM_HAS_HOST_IP=1
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOURCED:OK"* ]]
}

# --- Dynamic _start_proxy behaviour (uses python3 PATH shim) ---

@test "_start_proxy: PROXY_ENABLED=true with empty domains emits the WARN at runtime" {
  # No python3 needed — the WARN fires before _proxy_should_start || return.
  run _run_sandbox '_start_proxy 2>&1; true' \
    PROXY_ENABLED=true PROXY_ALLOW_DOMAINS=
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: proxy enabled but no proxy_allow_domains"* ]]
}

@test "_start_proxy: announces the proxy log path on stderr at runtime" {
  # Use the python3 shim to satisfy the FIFO read; _start_proxy will then
  # echo "[wrapper] proxy log: <path>" before checking kill -0.
  run _run_sandbox '_start_proxy 2>&1; true' \
    PROXY_ENABLED=true PROXY_ALLOW_DOMAINS=example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"proxy log: $_fake_tmpdir/proxy.log"* ]]
}

@test "_start_proxy: proxy log path is in the sandbox tmpdir regardless of AGENT_SANDBOX_DEBUG" {
  # Without AGENT_SANDBOX_DEBUG=1, the announced path must still point at
  # $_tmpdir/proxy.log — the unconditional persistence behaviour.
  run _run_sandbox '_start_proxy 2>&1; true' \
    PROXY_ENABLED=true PROXY_ALLOW_DOMAINS=example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"proxy log: $_fake_tmpdir/proxy.log"* ]]
  [[ "$output" != *"proxy log: /dev/null"* ]]
}

@test "_start_proxy: PROXY_ENABLED=false does not announce a proxy log (regression a)" {
  run _run_sandbox '_start_proxy 2>&1; true' \
    PROXY_ENABLED=false PROXY_ALLOW_DOMAINS=example.com
  [ "$status" -eq 0 ]
  [[ "$output" != *"proxy log:"* ]]
  [[ "$output" != *"WARN:"* ]]
}
