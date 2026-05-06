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

@test "A1 add: Darwin success (find=empty, add=ok)" {
  # Linux failure tracked in Issue #66 (PATH shim or OS dispatch root cause)
  case "$OSTYPE" in linux*) skip "Linux failure tracked in #66" ;; esac
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=empty
  export MOCK_SEC_ADD_STATE=ok
  run bash -c 'printf "mynewtoken\n" | "$JAILRUN_DIR/jailrun" token add --name github:classic'
  [ "$status" -eq 0 ]
  [[ "$output" == *"saved"* ]]
  assert_shim_called security "find-generic-password -s jailrun:github:classic -a jailrun-test"
  assert_shim_called security "add-generic-password -s jailrun:github:classic -a jailrun-test"
}

@test "A1L add: Linux success (lookup=empty, store=ok)" {
  # Linux failure tracked in Issue #66 (PATH shim or OS dispatch root cause)
  case "$OSTYPE" in linux*) skip "Linux failure tracked in #66" ;; esac
  export MOCK_UNAME=Linux
  export MOCK_SECTOOL_LOOKUP_STATE=empty
  export MOCK_SECTOOL_STORE_STATE=ok
  run bash -c 'printf "mynewtoken\n" | "$JAILRUN_DIR/jailrun" token add --name github:classic'
  [ "$status" -eq 0 ]
  [[ "$output" == *"saved"* ]]
  assert_shim_called "secret-tool" "lookup service jailrun:github:classic account jailrun-test"
  assert_shim_called "secret-tool" "store --label=jailrun:github:classic service jailrun:github:classic account jailrun-test"
}

@test "A2 add: Darwin Keychain failure (find=fail, add=fail)" {
  # Linux failure tracked in Issue #66 (PATH shim or OS dispatch root cause)
  case "$OSTYPE" in linux*) skip "Linux failure tracked in #66" ;; esac
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=fail
  export MOCK_SEC_ADD_STATE=fail
  run bash -c 'printf "mynewtoken\n" | "$JAILRUN_DIR/jailrun" token add --name github:classic'
  [ "$status" -ne 0 ]
  # fail 吸収後に add 経路まで進んだこと (add が呼ばれて失敗した) を確認
  assert_shim_called security "find-generic-password -s jailrun:github:classic -a jailrun-test"
  assert_shim_called security "add-generic-password -s jailrun:github:classic -a jailrun-test"
}

@test "A3 add: invalid arg (--name missing)" {
  export MOCK_UNAME=Darwin
  run _jailrun_token add
  [ "$status" -eq 1 ]
  [[ "$output" == *"--name is required"* ]]
}

@test "A4 add: invalid arg (unknown option)" {
  export MOCK_UNAME=Darwin
  run _jailrun_token add --name foo --other
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option"* ]]
}

# ------------------------------------------------------------------------
# Cycle v0.3.3 / Unit 002 / Issue #57
# Spec: .aidlc/cycles/v0.3.3/design-artifacts/logical-designs/
#       unit_002_token_cmd_tty_echo_restore_logical_design.md
# Hybrid pattern (_rc capture + INT/TERM scoped trap) verification
# ------------------------------------------------------------------------

@test "AE1 add: non-tty EOF (no Keychain side-effect, _rc capture)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=empty
  export MOCK_SEC_ADD_STATE=ok
  # 即 EOF (パイプ閉じ) で read _token が失敗
  run bash -c 'printf "" | "$JAILRUN_DIR/jailrun" token add --name github:classic'
  [ "$status" -ne 0 ]
  # ガードによりスキップされ stty: stdin isn't a terminal は出ない
  [[ "$output" != *"stty: stdin isn't a terminal"* ]]
  # _rc capture により return が走り Keychain への書き込みは発生しない
  assert_shim_not_called security "add-generic-password"
  # 非 tty では stty 自体も呼ばれない
  assert_shim_not_called stty
}

# ========================================================================
# _cmd_rotate
# ========================================================================

@test "R1 rotate: Darwin success (find=registered, delete=ok, add=ok)" {
  # Linux failure tracked in Issue #66 (PATH shim or OS dispatch root cause)
  case "$OSTYPE" in linux*) skip "Linux failure tracked in #66" ;; esac
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

@test "R1L rotate: Linux success (lookup=registered, clear=ok, store=ok)" {
  # Linux failure tracked in Issue #66 (PATH shim or OS dispatch root cause)
  case "$OSTYPE" in linux*) skip "Linux failure tracked in #66" ;; esac
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

@test "R2 rotate: Darwin unregistered (find=empty)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=empty
  run bash -c '"$JAILRUN_DIR/jailrun" token rotate --name github:classic'
  [ "$status" -eq 1 ]
  [[ "$output" == *"not registered"* ]]
}

@test "R2b rotate: Darwin Keychain failure (find=fail, same as empty)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=fail
  run bash -c '"$JAILRUN_DIR/jailrun" token rotate --name github:classic'
  [ "$status" -eq 1 ]
  [[ "$output" == *"not registered"* ]]
}

@test "R3 rotate: invalid arg (--name missing)" {
  export MOCK_UNAME=Darwin
  run _jailrun_token rotate
  [ "$status" -eq 1 ]
  [[ "$output" == *"--name is required"* ]]
}

# ------------------------------------------------------------------------
# Non-tty guard cases (Cycle v0.3.2 / Unit 001 / Issue #52)
# Spec: .aidlc/cycles/v0.3.2/design-artifacts/logical-designs/
#       unit_001_token_rotate_tty_guard_logical_design.md
# ------------------------------------------------------------------------

@test "R4 rotate: non-tty normal input (guard skips stty, Keychain updated)" {
  # Linux failure tracked in Issue #66 (PATH shim or OS dispatch root cause)
  case "$OSTYPE" in linux*) skip "Linux failure tracked in #66" ;; esac
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=registered
  export MOCK_SEC_DELETE_STATE=ok
  export MOCK_SEC_ADD_STATE=ok
  run bash -c 'printf "y\nnewtok\n" | "$JAILRUN_DIR/jailrun" token rotate --name github:classic'
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated"* ]]
  # ガードが機能して非 tty 環境では stty が呼ばれないことを確認
  assert_shim_not_called stty
  # Keychain delete + add の順序確認 (R1 と同じ動作を保証)
  _del_line=$(grep -n $'^security\tdelete-generic-password' "$SHIM_CALLS_LOG" | head -1 | cut -d: -f1)
  _add_line=$(grep -n $'^security\tadd-generic-password' "$SHIM_CALLS_LOG" | head -1 | cut -d: -f1)
  [ -n "$_del_line" ]
  [ -n "$_add_line" ]
  [ "$_del_line" -lt "$_add_line" ]
}

@test "R5 rotate: non-tty EOF (token input, no Keychain side-effect)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=registered
  # confirm に y を渡した後、トークン入力で EOF (パイプ閉じ)
  run bash -c 'printf "y\n" | "$JAILRUN_DIR/jailrun" token rotate --name github:classic'
  # set -eu 下で read _token が EOF で失敗 → 関数停止 (厳密なコード値は問わず非 0 のみ確認)
  [ "$status" -ne 0 ]
  # ガードによりスキップされ "stty: stdin isn't a terminal" は出ない
  [[ "$output" != *"stty: stdin isn't a terminal"* ]]
  # Keychain への副作用なし (delete / add が呼ばれない)
  assert_shim_not_called security "delete-generic-password"
  assert_shim_not_called security "add-generic-password"
  # 非 tty では stty 自体も呼ばれない
  assert_shim_not_called stty
}

@test "R6 rotate: non-tty empty input (empty input, skipping)" {
  # Linux failure tracked in Issue #66 (PATH shim or OS dispatch root cause)
  case "$OSTYPE" in linux*) skip "Linux failure tracked in #66" ;; esac
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=registered
  # confirm に y、トークン入力に空行 (改行のみ)
  run bash -c 'printf "y\n\n" | "$JAILRUN_DIR/jailrun" token rotate --name github:classic'
  [ "$status" -eq 0 ]
  [[ "$output" == *"empty input, skipping"* ]]
  # 空入力時は Keychain 更新が走らないことを確認
  assert_shim_not_called security "delete-generic-password"
  assert_shim_not_called security "add-generic-password"
  # 非 tty では stty 自体も呼ばれない
  assert_shim_not_called stty
}

# ------------------------------------------------------------------------
# Cycle v0.3.3 / Unit 002 / Issue #57
# trap -p invariant: 関数完走後に呼び出し元 trap 状態に差分がないこと
# ⚠ パイプライン (`printf ... | _cmd_*`) は subshell 実行で trap を観測
#   できないため、stdin はファイル経由で渡し、関数を **親シェル**で実行する
# ------------------------------------------------------------------------

@test "RT1 rotate: trap -p no diff (source-based, file redirect)" {
  setup_jailrun_env
  setup_token_shims
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=registered
  export MOCK_SEC_DELETE_STATE=ok
  export MOCK_SEC_ADD_STATE=ok
  run bash -c '
    set -eu
    export _JAILRUN_TOKEN_NODISPATCH=1
    . "$JAILRUN_LIB/token.sh"
    USER=jailrun-test
    TMPIN="$BATS_TEST_TMPDIR/rt1-input"
    printf "y\nnewtok\n" > "$TMPIN"
    BEFORE=$(trap -p)
    _cmd_rotate --name github:classic < "$TMPIN" >/dev/null
    AFTER=$(trap -p)
    [ "$BEFORE" = "$AFTER" ]
  '
  [ "$status" -eq 0 ]
}

@test "AT1 add: trap -p no diff (source-based, file redirect)" {
  setup_jailrun_env
  setup_token_shims
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=empty
  export MOCK_SEC_ADD_STATE=ok
  run bash -c '
    set -eu
    export _JAILRUN_TOKEN_NODISPATCH=1
    . "$JAILRUN_LIB/token.sh"
    USER=jailrun-test
    TMPIN="$BATS_TEST_TMPDIR/at1-input"
    printf "newtok\n" > "$TMPIN"
    BEFORE=$(trap -p)
    _cmd_add --name github:classic < "$TMPIN" >/dev/null
    AFTER=$(trap -p)
    [ "$BEFORE" = "$AFTER" ]
  '
  [ "$status" -eq 0 ]
}

# ------------------------------------------------------------------------
# Cycle v0.3.3 / Operations Phase レビュー反映
# 呼び出し元の事前 INT/TERM trap を保持すること
# ------------------------------------------------------------------------

@test "RT2 rotate: preserves caller pre-existing INT/TERM trap" {
  setup_jailrun_env
  setup_token_shims
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=registered
  export MOCK_SEC_DELETE_STATE=ok
  export MOCK_SEC_ADD_STATE=ok
  run bash -c '
    set -eu
    export _JAILRUN_TOKEN_NODISPATCH=1
    . "$JAILRUN_LIB/token.sh"
    USER=jailrun-test
    TMPIN="$BATS_TEST_TMPDIR/rt2-input"
    printf "y\nnewtok\n" > "$TMPIN"
    trap "echo caller_int_handler" INT
    trap "echo caller_term_handler" TERM
    BEFORE=$(trap -p INT TERM)
    _cmd_rotate --name github:classic < "$TMPIN" >/dev/null
    AFTER=$(trap -p INT TERM)
    [ "$BEFORE" = "$AFTER" ]
  '
  [ "$status" -eq 0 ]
}

@test "AT2 add: preserves caller pre-existing INT/TERM trap" {
  setup_jailrun_env
  setup_token_shims
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=empty
  export MOCK_SEC_ADD_STATE=ok
  run bash -c '
    set -eu
    export _JAILRUN_TOKEN_NODISPATCH=1
    . "$JAILRUN_LIB/token.sh"
    USER=jailrun-test
    TMPIN="$BATS_TEST_TMPDIR/at2-input"
    printf "newtok\n" > "$TMPIN"
    trap "echo caller_int_handler" INT
    trap "echo caller_term_handler" TERM
    BEFORE=$(trap -p INT TERM)
    _cmd_add --name github:classic < "$TMPIN" >/dev/null
    AFTER=$(trap -p INT TERM)
    [ "$BEFORE" = "$AFTER" ]
  '
  [ "$status" -eq 0 ]
}

# ========================================================================
# _cmd_delete
# ========================================================================

@test "D1 delete: Darwin success (find=registered, delete=ok)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=registered
  export MOCK_SEC_DELETE_STATE=ok
  run bash -c 'printf "y\n" | "$JAILRUN_DIR/jailrun" token delete --name github:classic'
  [ "$status" -eq 0 ]
  [[ "$output" == *"deleted"* ]]
  assert_shim_called security "delete-generic-password -s jailrun:github:classic -a jailrun-test"
}

@test "D1L delete: Linux success (lookup=registered, clear=ok)" {
  export MOCK_UNAME=Linux
  export MOCK_SECTOOL_LOOKUP_STATE=registered
  export MOCK_SECTOOL_CLEAR_STATE=ok
  run bash -c 'printf "y\n" | "$JAILRUN_DIR/jailrun" token delete --name github:classic'
  [ "$status" -eq 0 ]
  [[ "$output" == *"deleted"* ]]
  assert_shim_called "secret-tool" "clear service jailrun:github:classic account jailrun-test"
}

@test "D2 delete: Darwin unregistered (find=empty)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=empty
  run _jailrun_token delete --name github:classic
  [ "$status" -eq 1 ]
  [[ "$output" == *"not registered"* ]]
}

@test "D2b delete: Darwin Keychain failure (find=fail, same as empty)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_FIND_STATE=fail
  run _jailrun_token delete --name github:classic
  [ "$status" -eq 1 ]
  [[ "$output" == *"not registered"* ]]
}

@test "D3 delete: invalid arg (--name missing)" {
  export MOCK_UNAME=Darwin
  run _jailrun_token delete
  [ "$status" -eq 1 ]
  [[ "$output" == *"--name is required"* ]]
}

# ========================================================================
# _cmd_list
# ========================================================================

@test "L1 list: Darwin success (dump 2 entries + 1 unrelated, find=registered)" {
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

@test "L2a list: Darwin no registered (dump=empty)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_DUMP_STATE=empty
  run _jailrun_token list
  [ "$status" -eq 0 ]
  [[ "$output" == *"no tokens registered"* ]]
}

@test "L2b list: Darwin security failure (dump=fail, same as empty)" {
  export MOCK_UNAME=Darwin
  export MOCK_SEC_DUMP_STATE=fail
  run _jailrun_token list
  [ "$status" -eq 0 ]
  [[ "$output" == *"no tokens registered"* ]]
}

@test "L3 list: Linux branch (uname=Linux)" {
  export MOCK_UNAME=Linux
  run _jailrun_token list
  [ "$status" -eq 0 ]
  # Linux list writes the hint to stderr; bats `run` captures both streams in $output.
  [[ "$output" == *"specify a known token name"* ]]
}
