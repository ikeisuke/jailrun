#!/usr/bin/env bats

# Cycle v0.3.6 / Unit 001 / Issue #77
# Verifies that `make install` distributes lib/platform/sandbox-linux-apparmor.sh.
# Prior to v0.3.6 the install target omitted this file, breaking the
# AppArmor-primary sandbox path on Linux / WSL2.

load helpers

setup() {
  setup_jailrun_env
  _install_prefix="$(mktemp -d)"
  export _install_prefix
}

teardown() {
  rm -rf "$_install_prefix"
}

@test "make install distributes sandbox-linux-apparmor.sh" {
  _repo_root="$BATS_TEST_DIRNAME/.."
  run make -C "$_repo_root" install PREFIX="$_install_prefix"
  [ "$status" -eq 0 ]
  [ -f "$_install_prefix/lib/jailrun/platform/sandbox-linux-apparmor.sh" ]
}

@test "make install distributes the existing sandbox platform backends" {
  _repo_root="$BATS_TEST_DIRNAME/.."
  run make -C "$_repo_root" install PREFIX="$_install_prefix"
  [ "$status" -eq 0 ]
  # Regression: previously-shipped backends remain in place after the addition.
  [ -f "$_install_prefix/lib/jailrun/platform/sandbox-linux.sh" ]
  [ -f "$_install_prefix/lib/jailrun/platform/sandbox-linux-systemd.sh" ]
  [ -f "$_install_prefix/lib/jailrun/platform/sandbox-darwin.sh" ]
}
