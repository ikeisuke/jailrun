#!/usr/bin/env bats

@test "jailrun --help exits 0 and shows usage" {
  run bin/jailrun --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: jailrun"* ]]
}

@test "jailrun --version shows version" {
  run bin/jailrun --version
  [ "$status" -eq 0 ]
  [[ "$output" == "jailrun 0.1.0" ]]
}

@test "jailrun with unknown command exits 1" {
  run bin/jailrun nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown command"* ]]
}

@test "jailrun with no args shows help" {
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
