#!/usr/bin/env bats

load helpers

# Test Codex argument rewriting with a fake codex binary that prints args
setup() {
  setup_jailrun_env
  TMPBIN=$(mktemp -d)
  # Fake codex that prints each argument on a separate line, angle-bracketed
  cat > "$TMPBIN/codex" <<'SCRIPT'
#!/bin/sh
for arg; do printf '<%s>\n' "$arg"; done
SCRIPT
  chmod +x "$TMPBIN/codex"
}

teardown() {
  rm -rf "$TMPBIN"
}

@test "codex exec inserts -s danger-full-access" {
  export PATH="$TMPBIN:$PATH"
  export WRAPPER_NAME=codex
  export _CREDENTIAL_GUARD_SANDBOXED=1
  run sh -c '. "$JAILRUN_LIB/agent-wrapper.sh"' -- exec "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<exec>"* ]]
  [[ "$output" == *"<-s>"* ]]
  [[ "$output" == *"<danger-full-access>"* ]]
  [[ "$output" == *"<hello world>"* ]]
}

@test "codex review inserts -c sandbox_mode" {
  export PATH="$TMPBIN:$PATH"
  export WRAPPER_NAME=codex
  export _CREDENTIAL_GUARD_SANDBOXED=1
  run sh -c '. "$JAILRUN_LIB/agent-wrapper.sh"' -- review --base main
  [ "$status" -eq 0 ]
  [[ "$output" == *"<review>"* ]]
  [[ "$output" == *"<-c>"* ]]
  [[ "$output" == *"sandbox_mode"* ]]
  [[ "$output" == *"<--base>"* ]]
  [[ "$output" == *"<main>"* ]]
}

@test "codex exec preserves argument with newline" {
  export PATH="$TMPBIN:$PATH"
  export WRAPPER_NAME=codex
  export _CREDENTIAL_GUARD_SANDBOXED=1
  # Argument containing a literal newline
  run sh -c '. "$JAILRUN_LIB/agent-wrapper.sh"' -- exec "line1
line2"
  [ "$status" -eq 0 ]
  # The multi-line argument should appear as a single <line1\nline2> entry
  [[ "$output" == *"<line1"* ]]
  [[ "$output" == *"line2>"* ]]
}

@test "codex strips user --sandbox flag" {
  export PATH="$TMPBIN:$PATH"
  export WRAPPER_NAME=codex
  export _CREDENTIAL_GUARD_SANDBOXED=1
  run sh -c '. "$JAILRUN_LIB/agent-wrapper.sh"' -- exec --sandbox mymode "do stuff"
  [ "$status" -eq 0 ]
  # --sandbox and mymode should be stripped
  [[ "$output" != *"<mymode>"* ]]
  [[ "$output" != *"<--sandbox>"* ]]
  # -s danger-full-access should be inserted
  [[ "$output" == *"<-s>"* ]]
  [[ "$output" == *"<danger-full-access>"* ]]
}
