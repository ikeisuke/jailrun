#!/usr/bin/env bats

# bin/jailrun always auto-resolves JAILRUN_LIB from $0 (security: avoids
# attacker-controlled env-var injection). Tests that need an alternative SoT
# build a full install-tree fixture under $BATS_TEST_TMPDIR (see helper
# below) instead of overriding JAILRUN_LIB.
#
# The setup hook unsets any ambient JAILRUN_LIB inherited from the user's
# shell so the inheritance does not confuse downstream observations.
setup() {
  unset JAILRUN_LIB
}

# Build a self-contained jailrun install-tree under $BATS_TEST_TMPDIR/$1.
# $1: relative subdirectory name (e.g. "tree-override")
# $2: bash source body to APPEND to lib/subcmd-registry.sh (after the production
#     contents are copied in, so the body can override JAILRUN_AGENT_SUBCOMMANDS)
# Echoes the absolute path to the install-tree bin/jailrun binary.
_subcmd_registry_make_install_tree() {
  local _name="$1"
  local _append_body="$2"
  local _repo_root="$BATS_TEST_DIRNAME/.."
  local _root="$BATS_TEST_TMPDIR/$_name"
  mkdir -p "$_root/bin" "$_root/lib/jailrun"
  cp "$_repo_root/bin/jailrun" "$_root/bin/jailrun"
  chmod +x "$_root/bin/jailrun"
  cp "$_repo_root/lib/subcmd-registry.sh" "$_root/lib/jailrun/subcmd-registry.sh"
  if [ -n "$_append_body" ]; then
    printf '\n%s\n' "$_append_body" >> "$_root/lib/jailrun/subcmd-registry.sh"
  fi
  cat > "$_root/lib/jailrun/agent-wrapper.sh" <<'EOF'
#!/bin/sh
echo "STUB_WRAPPER_NAME=$WRAPPER_NAME args=$*"
exit 0
EOF
  chmod +x "$_root/lib/jailrun/agent-wrapper.sh"
  echo "$_root/bin/jailrun"
}

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

@test "jailrun --help lists copilot command" {
  run bin/jailrun --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"copilot"* ]]
  [[ "$output" == *"GitHub Copilot CLI"* ]]
}

# ---------------------------------------------------------------------------
# Unit 005 (subcmd-registry-single-source) integration tests
#
# Spec: .aidlc/cycles/v0.6.0/design-artifacts/logical-designs/
#       unit_005_subcmd_registry_single_source_logical_design.md
# ---------------------------------------------------------------------------

# Test 1: SoT contents (production registry sources cleanly and declares 6 entries in order).
@test "subcmd registry: JAILRUN_AGENT_SUBCOMMANDS lists the 6 agent subcmds in order" {
  # shellcheck disable=SC1091
  . "$BATS_TEST_DIRNAME/../lib/subcmd-registry.sh"
  [ "${#JAILRUN_AGENT_SUBCOMMANDS[@]}" -eq 6 ]
  [ "${JAILRUN_AGENT_SUBCOMMANDS[0]}" = "claude:launch Claude Code" ]
  [ "${JAILRUN_AGENT_SUBCOMMANDS[1]}" = "codex:launch Codex" ]
  [ "${JAILRUN_AGENT_SUBCOMMANDS[2]}" = "gemini:launch Gemini CLI" ]
  [ "${JAILRUN_AGENT_SUBCOMMANDS[3]}" = "kiro-cli:launch Kiro CLI" ]
  [ "${JAILRUN_AGENT_SUBCOMMANDS[4]}" = "kiro-cli-chat:launch Kiro CLI Chat" ]
  [ "${JAILRUN_AGENT_SUBCOMMANDS[5]}" = "copilot:launch GitHub Copilot CLI" ]
}

# Test 3: --help Commands section contains the 6 agent rows derived from the SoT.
@test "subcmd registry: --help Commands section lists all 6 agent subcmds with descriptions" {
  run bin/jailrun --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"  claude              launch Claude Code"* ]]
  [[ "$output" == *"  codex               launch Codex"* ]]
  [[ "$output" == *"  gemini              launch Gemini CLI"* ]]
  [[ "$output" == *"  kiro-cli            launch Kiro CLI"* ]]
  [[ "$output" == *"  kiro-cli-chat       launch Kiro CLI Chat"* ]]
  [[ "$output" == *"  copilot             launch GitHub Copilot CLI"* ]]
}

# Test 4: SoT override drives both dispatch and --help simultaneously.
# Fixture: a self-contained install-tree under $BATS_TEST_TMPDIR/tree-override
# so JAILRUN_LIB auto-resolves to the fixture without env-var injection. The
# fixture's subcmd-registry.sh keeps the production helpers and only overrides
# JAILRUN_AGENT_SUBCOMMANDS. agent-wrapper.sh is a stub.
@test "subcmd registry: SoT override drives both dispatch and --help (production helpers via fixture)" {
  local _jailrun
  _jailrun=$(_subcmd_registry_make_install_tree tree-override 'JAILRUN_AGENT_SUBCOMMANDS=("foo:launch Foo")')

  # 4a: dispatch derivation — fixture bin/jailrun foo reaches the stub agent-wrapper.
  run "$_jailrun" foo extra arg
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB_WRAPPER_NAME=foo args=extra arg"* ]]

  # 4b: help derivation — Commands section between "Commands:" and "Environment:"
  # must contain the overridden "foo" row and must NOT contain any of the
  # production agent rows (Commands rows have leading two-space indent;
  # Examples rows are excluded by the section slice).
  run "$_jailrun" --help
  [ "$status" -eq 0 ]
  local _commands_section
  _commands_section=$(printf '%s\n' "$output" | awk '/^Commands:/{flag=1;next} /^Environment:/{flag=0} flag')
  [[ "$_commands_section" == *"  foo                 launch Foo"* ]]
  ! printf '%s' "$_commands_section" | grep -qE '^  claude '
  ! printf '%s' "$_commands_section" | grep -qE '^  codex '
  ! printf '%s' "$_commands_section" | grep -qE '^  gemini '
  ! printf '%s' "$_commands_section" | grep -qE '^  kiro-cli '
  ! printf '%s' "$_commands_section" | grep -qE '^  kiro-cli-chat '
  ! printf '%s' "$_commands_section" | grep -qE '^  copilot '
}

# Test 6: validate fail-fast covers format / uniqueness / reserved-name collision.
# Uses the same install-tree fixture pattern as Test 4, with a per-test
# subdirectory so each invalid case is isolated.
_subcmd_registry_run_invalid_sot() {
  local _override_array="$1"
  local _jailrun
  _jailrun=$(_subcmd_registry_make_install_tree "tree-invalid-$BATS_TEST_NUMBER" "$_override_array")
  run "$_jailrun" --help
}

@test "subcmd registry validator: rejects empty entry" {
  _subcmd_registry_run_invalid_sot 'JAILRUN_AGENT_SUBCOMMANDS=("")'
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid JAILRUN_AGENT_SUBCOMMANDS entry"* ]]
}

@test "subcmd registry validator: rejects entry without colon" {
  _subcmd_registry_run_invalid_sot 'JAILRUN_AGENT_SUBCOMMANDS=("foo")'
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid JAILRUN_AGENT_SUBCOMMANDS entry: \"foo\""* ]]
}

@test "subcmd registry validator: rejects empty name (':desc' form)" {
  _subcmd_registry_run_invalid_sot 'JAILRUN_AGENT_SUBCOMMANDS=(":launch Foo")'
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid JAILRUN_AGENT_SUBCOMMANDS entry"* ]]
}

@test "subcmd registry validator: rejects empty description ('name:' form)" {
  _subcmd_registry_run_invalid_sot 'JAILRUN_AGENT_SUBCOMMANDS=("foo:")'
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid JAILRUN_AGENT_SUBCOMMANDS entry: \"foo:\""* ]]
}

@test "subcmd registry validator: rejects duplicate names" {
  _subcmd_registry_run_invalid_sot 'JAILRUN_AGENT_SUBCOMMANDS=("foo:launch Foo" "foo:launch Foo 2")'
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate subcmd name \"foo\""* ]]
}

@test "subcmd registry validator: rejects reserved-name collision (token)" {
  _subcmd_registry_run_invalid_sot 'JAILRUN_AGENT_SUBCOMMANDS=("token:launch Token")'
  [ "$status" -eq 1 ]
  [[ "$output" == *"subcmd name \"token\""* ]]
  [[ "$output" == *"collides with reserved command"* ]]
}

# Test 8: production JAILRUN_LIB auto-resolution still works when JAILRUN_LIB
# is explicitly unset before invocation.
@test "subcmd registry: JAILRUN_LIB auto-resolution still works when unset" {
  run env -u JAILRUN_LIB bin/jailrun --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"  claude              launch Claude Code"* ]]
  [[ "$output" == *"  copilot             launch GitHub Copilot CLI"* ]]
}

# Test 9: security regression — ambient JAILRUN_LIB must be ignored by
# bin/jailrun (delta-14). A hostile fixture in JAILRUN_LIB must NOT be
# sourced. Production lib/jailrun must always be auto-resolved from $0.
@test "subcmd registry: JAILRUN_LIB env-var injection is ignored (security)" {
  local _hostile="$BATS_TEST_TMPDIR/hostile-lib"
  mkdir -p "$_hostile"
  cat > "$_hostile/subcmd-registry.sh" <<'EOF'
echo "HOSTILE_SOT_LOADED"
exit 42
EOF

  run env JAILRUN_LIB="$_hostile" bin/jailrun --help
  [ "$status" -eq 0 ]
  # Hostile marker must NOT appear; production output must still appear.
  ! printf '%s' "$output" | grep -q "HOSTILE_SOT_LOADED"
  [[ "$output" == *"  claude              launch Claude Code"* ]]
  [[ "$output" == *"  copilot             launch GitHub Copilot CLI"* ]]
}
