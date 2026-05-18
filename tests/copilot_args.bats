#!/usr/bin/env bats

# Unit 004 (#67) main regression test: ensure `jailrun copilot --resume` passes
# the `--resume` argv through to the real copilot binary without alteration.
#
# Strategy mirrors tests/codex_args.bats: a fake copilot binary in $TMPBIN
# prints each argument angle-bracketed; agent-wrapper.sh is sourced with
# _CREDENTIAL_GUARD_SANDBOXED=1 so the wrapper takes the already-sandboxed
# branch (case "$WRAPPER_NAME" in *) exec "$REAL_BIN" "$@";; esac) and
# delegates straight to the fake.

load helpers

setup() {
  setup_jailrun_env
  TMPBIN=$(mktemp -d)
  cat > "$TMPBIN/copilot" <<'SCRIPT'
#!/bin/sh
for arg; do printf '<%s>\n' "$arg"; done
SCRIPT
  chmod +x "$TMPBIN/copilot"
}

teardown() {
  rm -rf "$TMPBIN"
}

@test "copilot --resume passes through to real binary (main regression for #67)" {
  export PATH="$TMPBIN:$PATH"
  export WRAPPER_NAME=copilot
  export _CREDENTIAL_GUARD_SANDBOXED=1
  run sh -c '. "$JAILRUN_LIB/agent-wrapper.sh"' -- --resume
  [ "$status" -eq 0 ]
  [[ "$output" == *"<--resume>"* ]]
}

@test "copilot --help passes through without modification (auxiliary)" {
  export PATH="$TMPBIN:$PATH"
  export WRAPPER_NAME=copilot
  export _CREDENTIAL_GUARD_SANDBOXED=1
  run sh -c '. "$JAILRUN_LIB/agent-wrapper.sh"' -- --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"<--help>"* ]]
}

@test "copilot passes through multi-argument resume invocation (auxiliary)" {
  export PATH="$TMPBIN:$PATH"
  export WRAPPER_NAME=copilot
  export _CREDENTIAL_GUARD_SANDBOXED=1
  run sh -c '. "$JAILRUN_LIB/agent-wrapper.sh"' -- --resume my-session "extra arg"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<--resume>"* ]]
  [[ "$output" == *"<my-session>"* ]]
  [[ "$output" == *"<extra arg>"* ]]
}
