#!/usr/bin/env bats
#
# Tests for `jailrun token` subcommands (lib/token.sh).
# PATH shims (security / secret-tool / stty / uname / curl) are defined
# in tests/helpers.bash. Per-test behavior is controlled via MOCK_* env vars.
#
# Test case IDs correspond to:
#   .aidlc/cycles/v0.3.1/plans/unit-001-plan.md#テストケース設計

load helpers

setup() {
  setup_jailrun_env
  setup_token_shims
}

teardown() {
  teardown_token_shims
}

_jailrun_token() {
  "$JAILRUN_DIR/jailrun" token "$@"
}

# ========================================================================
# _cmd_add
# ========================================================================

@test "A1 add: Darwin 正常系 (find=empty, add=ok)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=empty
  export MOCK_SEC_ADD_STATE=ok
  run bash -c 'printf "mynewtoken\n" | "$JAILRUN_DIR/jailrun" token add --name github:classic'
  [ "$status" -eq 0 ]
  [[ "$output" == *"saved"* ]]
  assert_shim_called security "find-generic-password -s jailrun:github:classic -a jailrun-test"
  assert_shim_called security "add-generic-password -s jailrun:github:classic -a jailrun-test"
}

@test "A1L add: Linux 正常系 (lookup=empty, store=ok)" {
  export MOCK_UNAME=Linux
  export MOCK_SECTOOL_LOOKUP_STATE=empty
  export MOCK_SECTOOL_STORE_STATE=ok
  run bash -c 'printf "mynewtoken\n" | "$JAILRUN_DIR/jailrun" token add --name github:classic'
  [ "$status" -eq 0 ]
  [[ "$output" == *"saved"* ]]
  assert_shim_called "secret-tool" "lookup service jailrun:github:classic account jailrun-test"
  assert_shim_called "secret-tool" "store --label=jailrun:github:classic service jailrun:github:classic account jailrun-test"
}

@test "A2 add: Darwin Keychain 失敗 (find=fail, add=fail)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=fail
  export MOCK_SEC_ADD_STATE=fail
  run bash -c 'printf "mynewtoken\n" | "$JAILRUN_DIR/jailrun" token add --name github:classic'
  [ "$status" -ne 0 ]
  # fail 吸収後に add 経路まで進んだこと (add が呼ばれて失敗した) を確認
  assert_shim_called security "find-generic-password -s jailrun:github:classic -a jailrun-test"
  assert_shim_called security "add-generic-password -s jailrun:github:classic -a jailrun-test"
}

@test "A3 add: 不正引数 (--name 欠落)" {
  export MOCK_UNAME=Darwin
  run _jailrun_token add
  [ "$status" -eq 1 ]
  [[ "$output" == *"--name is required"* ]]
}

@test "A4 add: 不正引数 (未知オプション)" {
  export MOCK_UNAME=Darwin
  run _jailrun_token add --name foo --other
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option"* ]]
}

# ========================================================================
# _cmd_rotate
# ========================================================================

@test "R1 rotate: Darwin 正常系 (find=registered, delete=ok, add=ok)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=registered
  export MOCK_SEC_DELETE_STATE=ok
  export MOCK_SEC_ADD_STATE=ok
  run bash -c 'printf "y\nnewtok\n" | "$JAILRUN_DIR/jailrun" token rotate --name github:classic'
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated"* ]]
  # Order: delete before add
  # Extract the line numbers to verify ordering.
  _del_line=$(grep -n $'^security\tdelete-generic-password' "$SHIM_CALLS_LOG" | head -1 | cut -d: -f1)
  _add_line=$(grep -n $'^security\tadd-generic-password' "$SHIM_CALLS_LOG" | head -1 | cut -d: -f1)
  [ -n "$_del_line" ]
  [ -n "$_add_line" ]
  [ "$_del_line" -lt "$_add_line" ]
}

@test "R1L rotate: Linux 正常系 (lookup=registered, clear=ok, store=ok)" {
  export MOCK_UNAME=Linux
  export MOCK_SECTOOL_LOOKUP_STATE=registered
  export MOCK_SECTOOL_CLEAR_STATE=ok
  export MOCK_SECTOOL_STORE_STATE=ok
  run bash -c 'printf "y\nnewtok\n" | "$JAILRUN_DIR/jailrun" token rotate --name github:classic'
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated"* ]]
  _clr_line=$(grep -n $'^secret-tool\tclear' "$SHIM_CALLS_LOG" | head -1 | cut -d: -f1)
  _sto_line=$(grep -n $'^secret-tool\tstore' "$SHIM_CALLS_LOG" | head -1 | cut -d: -f1)
  [ -n "$_clr_line" ]
  [ -n "$_sto_line" ]
  [ "$_clr_line" -lt "$_sto_line" ]
}

@test "R2 rotate: Darwin 未登録 (find=empty)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=empty
  run bash -c '"$JAILRUN_DIR/jailrun" token rotate --name github:classic'
  [ "$status" -eq 1 ]
  [[ "$output" == *"not registered"* ]]
}

@test "R2b rotate: Darwin Keychain 失敗 (find=fail, empty と同値)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=fail
  run bash -c '"$JAILRUN_DIR/jailrun" token rotate --name github:classic'
  [ "$status" -eq 1 ]
  [[ "$output" == *"not registered"* ]]
}

@test "R3 rotate: 不正引数 (--name 欠落)" {
  export MOCK_UNAME=Darwin
  run _jailrun_token rotate
  [ "$status" -eq 1 ]
  [[ "$output" == *"--name is required"* ]]
}

# ========================================================================
# _cmd_delete
# ========================================================================

@test "D1 delete: Darwin 正常系 (find=registered, delete=ok)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=registered
  export MOCK_SEC_DELETE_STATE=ok
  run bash -c 'printf "y\n" | "$JAILRUN_DIR/jailrun" token delete --name github:classic'
  [ "$status" -eq 0 ]
  [[ "$output" == *"deleted"* ]]
  assert_shim_called security "delete-generic-password -s jailrun:github:classic -a jailrun-test"
}

@test "D1L delete: Linux 正常系 (lookup=registered, clear=ok)" {
  export MOCK_UNAME=Linux
  export MOCK_SECTOOL_LOOKUP_STATE=registered
  export MOCK_SECTOOL_CLEAR_STATE=ok
  run bash -c 'printf "y\n" | "$JAILRUN_DIR/jailrun" token delete --name github:classic'
  [ "$status" -eq 0 ]
  [[ "$output" == *"deleted"* ]]
  assert_shim_called "secret-tool" "clear service jailrun:github:classic account jailrun-test"
}

@test "D2 delete: Darwin 未登録 (find=empty)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=empty
  run _jailrun_token delete --name github:classic
  [ "$status" -eq 1 ]
  [[ "$output" == *"not registered"* ]]
}

@test "D2b delete: Darwin Keychain 失敗 (find=fail, empty と同値)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=fail
  run _jailrun_token delete --name github:classic
  [ "$status" -eq 1 ]
  [[ "$output" == *"not registered"* ]]
}

@test "D3 delete: 不正引数 (--name 欠落)" {
  export MOCK_UNAME=Darwin
  run _jailrun_token delete
  [ "$status" -eq 1 ]
  [[ "$output" == *"--name is required"* ]]
}

# ========================================================================
# _cmd_list
# ========================================================================

@test "L1 list: Darwin 正常系 (dump 2件 + 無関係1件, find=registered)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_DUMP_STATE=with_entries
  export MOCK_SEC_DUMP_OUTPUT='    "svce"<blob>="jailrun:github:classic"
    "svce"<blob>="jailrun:github:myorg"
    "svce"<blob>="com.apple.someapp.other"'
  export MOCK_SEC_FIND_STATE=registered
  export MOCK_TOKEN_VALUE=ghp_testtoken_for_shim_12345
  run _jailrun_token list
  [ "$status" -eq 0 ]
  # The unrelated service must not appear in the output.
  [[ "$output" != *"com.apple.someapp.other"* ]]
  # Output must be exactly 2 lines, each in `name<TAB>preview` format.
  [ "${#lines[@]}" -eq 2 ]
  _expected_preview=$(printf '%.12s...' "$MOCK_TOKEN_VALUE")
  [ "${lines[0]}" = "$(printf 'github:classic\t%s' "$_expected_preview")" ]
  [ "${lines[1]}" = "$(printf 'github:myorg\t%s' "$_expected_preview")" ]
  # Layer 1: dump-keychain was invoked.
  assert_shim_called security "dump-keychain"
  # Layer 2: find-generic-password invoked per jailrun: entry.
  assert_shim_called security "find-generic-password -s jailrun:github:classic -a jailrun-test"
  assert_shim_called security "find-generic-password -s jailrun:github:myorg -a jailrun-test"
  # The shim path does not call find for the unrelated service.
  assert_shim_not_called security "com.apple.someapp.other"
}

@test "L2a list: Darwin 登録なし (dump=empty)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_DUMP_STATE=empty
  run _jailrun_token list
  [ "$status" -eq 0 ]
  [[ "$output" == *"no tokens registered"* ]]
}

@test "L2b list: Darwin security 失敗 (dump=fail, empty と同値)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_DUMP_STATE=fail
  run _jailrun_token list
  [ "$status" -eq 0 ]
  [[ "$output" == *"no tokens registered"* ]]
}

@test "L3 list: Linux 分岐 (uname=Linux)" {
  export MOCK_UNAME=Linux
  run _jailrun_token list
  [ "$status" -eq 0 ]
  # Linux list writes the hint to stderr; bats `run` captures both streams in $output.
  [[ "$output" == *"specify a known token name"* ]]
}
