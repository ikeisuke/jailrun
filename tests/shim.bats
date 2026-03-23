#!/usr/bin/env bats

load helpers

@test "codex shim is a valid sh script" {
  run sh -n "$BATS_TEST_DIRNAME/../lib/shims/codex"
  [ "$status" -eq 0 ]
}

@test "codex shim contains exec jailrun codex" {
  run grep -q 'exec jailrun codex' "$BATS_TEST_DIRNAME/../lib/shims/codex"
  [ "$status" -eq 0 ]
}

@test "codex shim is 3 lines" {
  lines=$(wc -l < "$BATS_TEST_DIRNAME/../lib/shims/codex")
  [ "$lines" -eq 3 ]
}
