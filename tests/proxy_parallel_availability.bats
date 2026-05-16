#!/usr/bin/env bats

# Cycle v0.4.1 / Unit 002 / Issue #86 (M6 / T6)
# Parallel availability of lib/proxy.py inside the configured SoT range.
#
# Spawns N proxies in parallel for ITERATIONS rounds (Intent M6: N=10,
# 5 iterations = 50 attempts). Verifies that every bind lands inside
# [START, END] and that no two parallel processes pick the same port
# in a single iteration.
#
# Per cycle v0.4.1 Unit 002 logical design "収集規約":
#   PIDS / STDOUT_FILES / STDERR_FILES / PORTS share the same index i,
#   one process == one stdout file == one stderr file. Always
#   spawn -> readiness -> kill -> wait -> verify, with teardown() doing
#   defensive PID cleanup so leaks do not poison the next iteration.

load helpers

setup() {
  _repo_root="$BATS_TEST_DIRNAME/.."
  _proxy="$_repo_root/lib/proxy.py"
  _const="$_repo_root/lib/netns-const.sh"

  # shellcheck disable=SC1090
  . "$_const"
  _range_start="$JAILRUN_PROXY_PORT_RANGE_START"
  _range_end="$JAILRUN_PROXY_PORT_RANGE_END"

  PIDS=()
  STDOUT_FILES=()
  STDERR_FILES=()
}

teardown() {
  local pid
  for pid in "${PIDS[@]}"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
}

@test "proxy bind stays in range under N=10 parallel x 5 iterations" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 required"
  fi

  local N=10
  local ITERATIONS=5
  local i j

  for i in $(seq 1 "$ITERATIONS"); do
    PIDS=()
    STDOUT_FILES=()
    STDERR_FILES=()

    # spawn
    for j in $(seq 0 $((N - 1))); do
      local out="$BATS_TEST_TMPDIR/proxy.$i.$j.out"
      local err="$BATS_TEST_TMPDIR/proxy.$i.$j.err"
      STDOUT_FILES[j]="$out"
      STDERR_FILES[j]="$err"
      # --enforce-port-range matches the production netns invocation
      # (sandbox.sh passes this flag when _NETNS is set); we exercise
      # the same code path here to validate range capacity at N=10.
      python3 "$_proxy" --allow-domains test.invalid --bind 127.0.0.1 --enforce-port-range \
        >"$out" 2>"$err" &
      PIDS[j]=$!
    done

    # readiness + assert range
    local PORTS=()
    for j in $(seq 0 $((N - 1))); do
      local outfile="${STDOUT_FILES[$j]}"
      local errfile="${STDERR_FILES[$j]}"
      local k
      local ready=0
      for k in $(seq 1 30); do
        if [ -s "$outfile" ]; then
          ready=1
          break
        fi
        sleep 0.1
      done
      if [ "$ready" -ne 1 ]; then
        echo "iteration=$i slot=$j: proxy never produced a port within 3s" >&2
        cat "$errfile" >&2 || true
        false
      fi
      local port
      port=$(head -n 1 "$outfile")
      [ "$port" -ge "$_range_start" ]
      [ "$port" -le "$_range_end" ]
      PORTS[j]="$port"
    done

    # uniqueness within the iteration: 10 distinct ports.
    local unique_count
    unique_count=$(printf '%s\n' "${PORTS[@]}" | sort -u | wc -l | tr -d ' ')
    [ "$unique_count" -eq "$N" ]

    # kill + wait
    for j in $(seq 0 $((N - 1))); do
      kill "${PIDS[$j]}" 2>/dev/null || true
    done
    for j in $(seq 0 $((N - 1))); do
      wait "${PIDS[$j]}" 2>/dev/null || true
    done
    PIDS=()
    STDOUT_FILES=()
    STDERR_FILES=()
  done
}
