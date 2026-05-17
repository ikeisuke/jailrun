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

# --- Cycle v0.4.3 / Unit 003 / Issue #79 ---
# Makefile install で lib/platform/*.sh をパターン install 化したことに伴う
# 等価性検証 3 件。配布全体集合 (@test 1) はリリース範囲全体の退行検出、
# platform 配下集合 (@test 2) は wildcard パターン化の SoT 自動同期性、
# パーミッション (@test 3) は 644 維持を担保する。新規 @test は AGENTS.md
# 規約に従い "cd $_repo_root && make ..." 形式で -C を使わない。

@test "make install distributes the complete expected file set" {
  _repo_root="$BATS_TEST_DIRNAME/.."
  cd "$_repo_root"
  run make install PREFIX="$_install_prefix"
  [ "$status" -eq 0 ]
  local _actual
  _actual=$(cd "$_install_prefix" && find . -type f | sed 's|^\./||' | sort)
  # IMPORTANT: Update this expected list when Makefile install adds/removes
  # any file. The list mirrors the install target's payload as of v0.4.3.
  local _expected
  _expected=$(printf '%s\n' \
    bin/jailrun \
    lib/jailrun/agent-wrapper.sh \
    lib/jailrun/aws.sh \
    lib/jailrun/config-cmd.sh \
    lib/jailrun/config-defaults.sh \
    lib/jailrun/config.py \
    lib/jailrun/config.sh \
    lib/jailrun/config_cli.py \
    lib/jailrun/config_migrate.py \
    lib/jailrun/credential-guard.sh \
    lib/jailrun/credentials.sh \
    lib/jailrun/netns-const.sh \
    lib/jailrun/netns_const_loader.py \
    lib/jailrun/platform/git-worktree.sh \
    lib/jailrun/platform/keychain-darwin.sh \
    lib/jailrun/platform/keychain-linux.sh \
    lib/jailrun/platform/sandbox-darwin.sh \
    lib/jailrun/platform/sandbox-linux-apparmor.sh \
    lib/jailrun/platform/sandbox-linux-systemd.sh \
    lib/jailrun/platform/sandbox-linux.sh \
    lib/jailrun/proxy.py \
    lib/jailrun/ruleset.sh \
    lib/jailrun/sandbox.sh \
    lib/jailrun/shims/codex \
    lib/jailrun/token.sh \
    | sort)
  [ "$_expected" = "$_actual" ]
}

@test "make install distributes all lib/platform/*.sh via wildcard pattern" {
  _repo_root="$BATS_TEST_DIRNAME/.."
  cd "$_repo_root"
  run make install PREFIX="$_install_prefix"
  [ "$status" -eq 0 ]
  local _expected
  _expected=$(cd "$_repo_root/lib/platform" && ls *.sh | sort)
  local _actual
  _actual=$(cd "$_install_prefix/lib/jailrun/platform" && ls *.sh 2>/dev/null | sort)
  [ "$_expected" = "$_actual" ]
}

@test "make install preserves 644 permission on all lib/platform/*.sh" {
  _repo_root="$BATS_TEST_DIRNAME/.."
  cd "$_repo_root"
  run make install PREFIX="$_install_prefix"
  [ "$status" -eq 0 ]
  for _f in "$_install_prefix/lib/jailrun/platform"/*.sh; do
    if [ "$(uname)" = "Darwin" ]; then
      [ "$(stat -f '%A' "$_f")" = "644" ]
    else
      [ "$(stat -c '%a' "$_f")" = "644" ]
    fi
  done
}
