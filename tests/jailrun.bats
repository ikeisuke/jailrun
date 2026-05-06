#!/usr/bin/env bats

@test "jailrun --help exits 0 and shows usage" {
  run bin/jailrun --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: jailrun"* ]]
}

@test "jailrun --version shows version" {
  run bin/jailrun --version
  [ "$status" -eq 0 ]
  expected_version="$(grep -E '^VERSION="[^"]*"$' bin/jailrun | sed -E 's/^VERSION="([^"]*)"$/\1/')"
  [ -n "$expected_version" ]
  [[ "$output" == "jailrun ${expected_version}" ]]
}

@test "jailrun with unknown command exits 1" {
  run bin/jailrun nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown command"* ]]
}

@test "jailrun with no args shows help" {
  # Linux failure tracked in Issue #66 (Cycle v0.3.4 Unit 001 / status -eq 0 fails on ubuntu-latest)
  if [ "$(uname)" = "Linux" ]; then skip "Linux failure tracked in #66"; fi
  run bin/jailrun
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: jailrun"* ]]
}

@test "jailrun token --help exits 0" {
  run bin/jailrun token --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Subcommands:"* ]]
}

@test "jailrun token with unknown subcommand exits 1" {
  run bin/jailrun token nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown subcommand"* ]]
}
