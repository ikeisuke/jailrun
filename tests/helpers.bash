# Common test helpers

# Set up JAILRUN_DIR and JAILRUN_LIB pointing to repo's lib/
setup_jailrun_env() {
  export JAILRUN_DIR="$BATS_TEST_DIRNAME/../bin"
  export JAILRUN_LIB="$BATS_TEST_DIRNAME/../lib"
  export WRAPPER_NAME="claude"
}

# ----------------------------------------------------------------
# Unit 001 (token.bats) helpers — PATH shim based Mock Boundary
#
# Spec: .aidlc/cycles/v0.3.1/design-artifacts/logical-designs/
#       unit_001_token_bats_tests_logical_design.md
#
# Generates PATH shims in $BATS_TEST_TMPDIR/shim-bin/ that emulate
# security / secret-tool / stty / uname / curl. Behavior is driven
# by MOCK_* environment variables set per-test.
# ----------------------------------------------------------------

setup_token_shims() {
  mkdir -p "$BATS_TEST_TMPDIR/shim-bin"
  mkdir -p "$BATS_TEST_TMPDIR/home"

  _write_security_shim
  _write_secret_tool_shim
  _write_stty_shim
  _write_uname_shim
  _write_curl_shim

  chmod +x "$BATS_TEST_TMPDIR"/shim-bin/*

  export PATH="$BATS_TEST_TMPDIR/shim-bin:$PATH"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export USER="jailrun-test"
  export HOME="$BATS_TEST_TMPDIR/home"
  export SHIM_CALLS_LOG="$BATS_TEST_TMPDIR/shim-calls.log"

  : "${MOCK_TOKEN_VALUE:=ghp_testtoken_for_shim_12345}"
  export MOCK_TOKEN_VALUE

  : > "$SHIM_CALLS_LOG"
}

teardown_token_shims() {
  :
}

_write_security_shim() {
  cat > "$BATS_TEST_TMPDIR/shim-bin/security" <<'SHIM'
#!/bin/sh
_log() {
  printf 'security\t%s\t%s\n' "$*" "$1_exit" >> "$SHIM_CALLS_LOG" 2>/dev/null || true
}
_argv="$*"
_sub="${1:-}"
shift 2>/dev/null || true
case "$_sub" in
  find-generic-password)
    _state="${MOCK_SEC_FIND_STATE:-empty}"
    case "$_state" in
      empty)
        printf 'security\t%s\t0\n' "find-generic-password $*" >> "$SHIM_CALLS_LOG"
        exit 0
        ;;
      registered)
        printf '%s\n' "${MOCK_TOKEN_VALUE}"
        printf 'security\t%s\t0\n' "find-generic-password $*" >> "$SHIM_CALLS_LOG"
        exit 0
        ;;
      fail)
        echo "security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain." >&2
        printf 'security\t%s\t44\n' "find-generic-password $*" >> "$SHIM_CALLS_LOG"
        exit 44
        ;;
    esac
    ;;
  add-generic-password)
    _state="${MOCK_SEC_ADD_STATE:-ok}"
    case "$_state" in
      ok)
        printf 'security\t%s\t0\n' "add-generic-password $*" >> "$SHIM_CALLS_LOG"
        exit 0
        ;;
      fail)
        echo "security: SecKeychainItemCreateFromContent failed (-25299)" >&2
        printf 'security\t%s\t45\n' "add-generic-password $*" >> "$SHIM_CALLS_LOG"
        exit 45
        ;;
    esac
    ;;
  delete-generic-password)
    _state="${MOCK_SEC_DELETE_STATE:-ok}"
    case "$_state" in
      ok)
        printf 'security\t%s\t0\n' "delete-generic-password $*" >> "$SHIM_CALLS_LOG"
        exit 0
        ;;
      fail)
        printf 'security\t%s\t44\n' "delete-generic-password $*" >> "$SHIM_CALLS_LOG"
        exit 44
        ;;
    esac
    ;;
  dump-keychain)
    _state="${MOCK_SEC_DUMP_STATE:-empty}"
    case "$_state" in
      with_entries)
        printf '%s\n' "${MOCK_SEC_DUMP_OUTPUT:-}"
        printf 'security\t%s\t0\n' "dump-keychain $*" >> "$SHIM_CALLS_LOG"
        exit 0
        ;;
      empty)
        printf 'security\t%s\t0\n' "dump-keychain $*" >> "$SHIM_CALLS_LOG"
        exit 0
        ;;
      fail)
        echo "security: SecKeychainCopySearchList failed (-25300)" >&2
        printf 'security\t%s\t1\n' "dump-keychain $*" >> "$SHIM_CALLS_LOG"
        exit 1
        ;;
    esac
    ;;
  *)
    echo "[shim] unknown security subcommand: $_sub" >&2
    printf 'security\t%s\t1\n' "$_argv" >> "$SHIM_CALLS_LOG"
    exit 1
    ;;
esac
SHIM
}

_write_secret_tool_shim() {
  cat > "$BATS_TEST_TMPDIR/shim-bin/secret-tool" <<'SHIM'
#!/bin/sh
_argv="$*"
_sub="${1:-}"
shift 2>/dev/null || true
case "$_sub" in
  lookup)
    _state="${MOCK_SECTOOL_LOOKUP_STATE:-empty}"
    case "$_state" in
      empty)
        printf 'secret-tool\t%s\t0\n' "lookup $*" >> "$SHIM_CALLS_LOG"
        exit 0
        ;;
      registered)
        printf '%s' "${MOCK_TOKEN_VALUE}"
        printf 'secret-tool\t%s\t0\n' "lookup $*" >> "$SHIM_CALLS_LOG"
        exit 0
        ;;
      fail)
        printf 'secret-tool\t%s\t1\n' "lookup $*" >> "$SHIM_CALLS_LOG"
        exit 1
        ;;
    esac
    ;;
  store)
    _state="${MOCK_SECTOOL_STORE_STATE:-ok}"
    cat >/dev/null 2>&1 || true
    case "$_state" in
      ok)
        printf 'secret-tool\t%s\t0\n' "store $*" >> "$SHIM_CALLS_LOG"
        exit 0
        ;;
      fail)
        printf 'secret-tool\t%s\t1\n' "store $*" >> "$SHIM_CALLS_LOG"
        exit 1
        ;;
    esac
    ;;
  clear)
    _state="${MOCK_SECTOOL_CLEAR_STATE:-ok}"
    case "$_state" in
      ok)
        printf 'secret-tool\t%s\t0\n' "clear $*" >> "$SHIM_CALLS_LOG"
        exit 0
        ;;
      fail)
        printf 'secret-tool\t%s\t1\n' "clear $*" >> "$SHIM_CALLS_LOG"
        exit 1
        ;;
    esac
    ;;
  *)
    echo "[shim] unknown secret-tool subcommand: $_sub" >&2
    printf 'secret-tool\t%s\t1\n' "$_argv" >> "$SHIM_CALLS_LOG"
    exit 1
    ;;
esac
SHIM
}

_write_stty_shim() {
  cat > "$BATS_TEST_TMPDIR/shim-bin/stty" <<'SHIM'
#!/bin/sh
printf 'stty\t%s\t0\n' "$*" >> "$SHIM_CALLS_LOG"
exit 0
SHIM
}

_write_uname_shim() {
  cat > "$BATS_TEST_TMPDIR/shim-bin/uname" <<'SHIM'
#!/bin/sh
_os="${MOCK_UNAME:-Darwin}"
printf '%s\n' "$_os"
printf 'uname\t%s\t0\n' "$*" >> "$SHIM_CALLS_LOG"
exit 0
SHIM
}

_write_curl_shim() {
  cat > "$BATS_TEST_TMPDIR/shim-bin/curl" <<'SHIM'
#!/bin/sh
# Emulate `curl -sS -H ... -D - -o /dev/null https://...` used by
# _check_gh_expiration in lib/token.sh. Return a fixed header with
# no expiration token so the caller reports "unknown".
printf 'HTTP/2 200 \r\n'
printf 'content-type: application/json\r\n'
printf '\r\n'
printf 'curl\t%s\t0\n' "$*" >> "$SHIM_CALLS_LOG"
exit 0
SHIM
}

# assert_shim_called <command> [argv_substring]
#   Fails the bats test if no log line matches.
#   argv_substring is a literal substring (grep -F semantics; no glob expansion).
assert_shim_called() {
  local _cmd="$1"
  local _sub="${2:-}"
  while IFS=$'\t' read -r _c _argv _code; do
    if [ "$_c" = "$_cmd" ]; then
      if [ -z "$_sub" ]; then
        return 0
      fi
      if printf '%s' "$_argv" | grep -F -- "$_sub" >/dev/null 2>&1; then
        return 0
      fi
    fi
  done < "$SHIM_CALLS_LOG"
  echo "assert_shim_called FAILED: cmd='$_cmd' sub='$_sub'" >&2
  echo "--- shim-calls.log ---" >&2
  cat "$SHIM_CALLS_LOG" >&2
  return 1
}

# assert_shim_not_called <command> [argv_substring]
assert_shim_not_called() {
  local _cmd="$1"
  local _sub="${2:-}"
  while IFS=$'\t' read -r _c _argv _code; do
    if [ "$_c" = "$_cmd" ]; then
      if [ -z "$_sub" ]; then
        echo "assert_shim_not_called FAILED: cmd='$_cmd' was called" >&2
        return 1
      fi
      if printf '%s' "$_argv" | grep -F -- "$_sub" >/dev/null 2>&1; then
        echo "assert_shim_not_called FAILED: cmd='$_cmd' sub='$_sub' matched" >&2
        return 1
      fi
    fi
  done < "$SHIM_CALLS_LOG"
  return 0
}
