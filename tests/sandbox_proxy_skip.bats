#!/usr/bin/env bats

# Cycle v0.4.2 / Unit 003 (in-cycle expansion)
# Regression tests for lib/sandbox.sh _start_proxy() skip path.
#
# Background: under `set -e`, `_proxy_should_start || return` propagates
# exit code 1 from `_proxy_should_start` (return without arg returns the
# previous exit code), causing _start_sandbox to abort before agent exec
# in proxy-disabled environments (macOS Seatbelt, native Linux dev w/o
# proxy, etc). Fix: `_proxy_should_start || return 0`.
#
# Setup mirrors tests/proxy_readiness.bats: fake JAILRUN_LIB with
# sandbox.sh + netns-const.sh + platform stubs + PATH shims for `ip` and
# `python3`.

load helpers

setup() {
  setup_jailrun_env
  _fake_lib="$(mktemp -d)"
  export _fake_lib

  mkdir -p "$_fake_lib/platform" "$_fake_lib/shim-bin"

  cp "$JAILRUN_LIB/sandbox.sh" "$_fake_lib/sandbox.sh"
  cp "$JAILRUN_LIB/netns-const.sh" "$_fake_lib/netns-const.sh"
  printf '#!/bin/sh\n# stub for tests\n' > "$_fake_lib/platform/sandbox-darwin.sh"
  printf '#!/bin/sh\n# stub for tests\n' > "$_fake_lib/platform/sandbox-linux.sh"

  # Default `ip` shim: `netns list` emits nothing -> _NETNS stays empty
  # (top-level launch block at sandbox.sh:384 is skipped).
  cat > "$_fake_lib/shim-bin/ip" <<'SHIM'
#!/bin/sh
exit 0
SHIM
  chmod +x "$_fake_lib/shim-bin/ip"

  # `python3` shim used by Test 2 (positive path). Records argv,
  # emits a fake port to satisfy `read -r _proxy_port < $_fifo`
  # (sandbox.sh:430), then sleeps to stay alive long enough for
  # `kill -0 $_proxy_pid` (sandbox.sh:433) to succeed. `sleep` is
  # invoked without `exec` so the python3 shim process itself remains
  # addressable via $_PROXY_PID for deterministic cleanup
  # (design review Round 2 #1).
  cat > "$_fake_lib/shim-bin/python3" <<SHIM
#!/bin/sh
printf '%s\n' "\$@" >> "$_fake_lib/python3-args.log"
printf '12345\n'
sleep 30
SHIM
  chmod +x "$_fake_lib/shim-bin/python3"

  _fake_home="$(mktemp -d)"
  export _fake_home
  _fake_tmpdir="$(mktemp -d)"
  export _fake_tmpdir
}

teardown() {
  # Best-effort cleanup of any python3 shim left running by Test 2.
  if [ -n "${_LEAKED_PID:-}" ]; then
    kill "$_LEAKED_PID" 2>/dev/null || true
  fi
  rm -rf "$_fake_lib" "$_fake_home" "$_fake_tmpdir"
}

# --- Test 1: set -e regression防波堤 ---

@test "set -e + _proxy_should_start=1 path completes without abort (Issue regression)" {
  run env -i HOME="$_fake_home" \
    JAILRUN_LIB="$_fake_lib" \
    PATH="$_fake_lib/shim-bin:$PATH" \
    bash -ec "
      _tmpdir='$_fake_tmpdir'
      _WRAPPER_NAME=claude
      . '$_fake_lib/sandbox.sh'
      _proxy_should_start() { return 1; }
      _start_proxy
      echo OK
    "
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# --- Test 2: 正常系（proxy 起動コマンド発行 + _PROXY_PORT 取得）---

@test "_start_proxy invokes python3 proxy.py and sets _PROXY_PORT when _proxy_should_start=0" {
  run env -i HOME="$_fake_home" \
    JAILRUN_LIB="$_fake_lib" \
    PATH="$_fake_lib/shim-bin:$PATH" \
    bash -c "
      _tmpdir='$_fake_tmpdir'
      _WRAPPER_NAME=claude
      . '$_fake_lib/sandbox.sh'
      _proxy_should_start() { return 0; }
      PROXY_ALLOW_DOMAINS='example.com'
      _start_proxy
      echo \"PORT=\$_PROXY_PORT PID=\$_PROXY_PID\"
    "
  [ "$status" -eq 0 ]
  [ -f "$_fake_lib/python3-args.log" ]
  grep -q "proxy.py" "$_fake_lib/python3-args.log"
  grep -q -- "--allow-domains" "$_fake_lib/python3-args.log"
  [[ "$output" == *"PORT=12345"* ]]

  # Cleanup the python3 shim (sleep 30) via captured PID.
  _LEAKED_PID=$(printf '%s\n' "$output" | sed -n 's/.*PID=\([0-9][0-9]*\).*/\1/p')
  export _LEAKED_PID
}

# --- Test 3: 単体 return 0 確認 (set -e なし) ---

@test "_start_proxy returns 0 directly when _proxy_should_start returns 1" {
  run env -i HOME="$_fake_home" \
    JAILRUN_LIB="$_fake_lib" \
    PATH="$_fake_lib/shim-bin:$PATH" \
    bash -c "
      _tmpdir='$_fake_tmpdir'
      _WRAPPER_NAME=claude
      . '$_fake_lib/sandbox.sh'
      _proxy_should_start() { return 1; }
      _start_proxy
    "
  [ "$status" -eq 0 ]
}
