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

# ----------------------------------------------------------------
# Cross-platform file mode assertion (Cycle v0.3.2 / Unit 003)
#
# Spec: .aidlc/cycles/v0.3.2/design-artifacts/logical-designs/
#       unit_003_git_askpass_chmod_0700_logical_design.md
#
# Supported: Darwin (BSD stat -f %A) / Linux (GNU coreutils stat -c %a).
# Mode is normalized to 3-digit octal (leading 0 stripped) before compare.
# Returns: 0=match / 1=mismatch / 2=unsupported platform.
# ----------------------------------------------------------------

assert_file_mode() {
  local _path="$1"
  local _expected="$2"
  local _actual
  case "$(uname)" in
    Darwin)
      _actual=$(stat -f %A "$_path")
      ;;
    Linux)
      _actual=$(stat -c %a "$_path")
      ;;
    *)
      printf 'assert_file_mode: unsupported platform: %s\n' "$(uname)" >&2
      return 2
      ;;
  esac
  _actual="${_actual#0}"
  local _expected_norm="${_expected#0}"
  [ "$_actual" = "$_expected_norm" ] || {
    printf 'expected mode %s, got %s for %s\n' "$_expected_norm" "$_actual" "$_path" >&2
    return 1
  }
}

# ----------------------------------------------------------------
# Unit 002 (ruleset.bats) helpers — PATH shim + sysbin whitelist
#
# Spec: .aidlc/cycles/v0.3.1/design-artifacts/logical-designs/
#       unit_002_ruleset_bats_tests_logical_design.md
#
# Strongly isolates PATH to $BATS_TEST_TMPDIR/shim-bin:$BATS_TEST_TMPDIR/sysbin
# (no /usr/bin, no /bin). sysbin holds symlinks to a whitelist of system
# binaries needed by bin/jailrun + lib/ruleset.sh + bats test code.
# shim-calls.log is a 6-column TSV:
#   command<TAB>category<TAB>method<TAB>argv<TAB>target<TAB>last
# where `last` is exit_code for normal rows, payload_path for api_payload
# auxiliary rows (switched by category column).
# ----------------------------------------------------------------

setup_ruleset_shims() {
  mkdir -p "$BATS_TEST_TMPDIR/shim-bin"
  mkdir -p "$BATS_TEST_TMPDIR/sysbin"
  mkdir -p "$BATS_TEST_TMPDIR/home"

  _ruleset_link_sysbin_whitelist || return 1

  _write_gh_shim
  _write_git_shim

  chmod +x "$BATS_TEST_TMPDIR/shim-bin"/*

  export PATH="$BATS_TEST_TMPDIR/shim-bin:$BATS_TEST_TMPDIR/sysbin"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export USER="jailrun-test"
  export HOME="$BATS_TEST_TMPDIR/home"
  export SHIM_CALLS_LOG="$BATS_TEST_TMPDIR/shim-calls.log"
  export GH_PAYLOAD_SEQ="$BATS_TEST_TMPDIR/gh-payload-seq"

  : > "$SHIM_CALLS_LOG"
  echo 0 > "$GH_PAYLOAD_SEQ"
}

teardown_ruleset_shims() {
  :
}

# Symlink a whitelist of system binaries from /usr/bin (preferred) or /bin
# into $BATS_TEST_TMPDIR/sysbin. gh must NEVER be in this whitelist.
_ruleset_link_sysbin_whitelist() {
  local _cmd
  for _cmd in readlink dirname cat grep rm chmod; do
    if [ -x "/usr/bin/$_cmd" ]; then
      ln -sf "/usr/bin/$_cmd" "$BATS_TEST_TMPDIR/sysbin/$_cmd"
    elif [ -x "/bin/$_cmd" ]; then
      ln -sf "/bin/$_cmd" "$BATS_TEST_TMPDIR/sysbin/$_cmd"
    else
      echo "[setup_ruleset_shims] ERROR: required system binary $_cmd not found in /usr/bin or /bin" >&2
      return 1
    fi
  done
}

_write_gh_shim() {
  cat > "$BATS_TEST_TMPDIR/shim-bin/gh" <<'SHIM'
#!/bin/sh
_argv="$*"
_sub="${1:-}"

# gh auth status
if [ "$_sub" = "auth" ]; then
  shift
  _argv_rest="$*"
  _state="${MOCK_GH_AUTH_STATE:-ok}"
  case "$_state" in
    ok)
      printf 'gh\tapi\t-\t%s\t-\t0\n' "$_argv_rest" >> "$SHIM_CALLS_LOG"
      exit 0
      ;;
    fail)
      echo "You are not logged into any GitHub hosts." >&2
      printf 'gh\tapi\t-\t%s\t-\t1\n' "$_argv_rest" >> "$SHIM_CALLS_LOG"
      exit 1
      ;;
  esac
fi

# gh api ...
if [ "$_sub" = "api" ]; then
  shift
  _argv_rest="$*"

  # Detect --method POST
  _method="GET"
  _has_post=0
  _has_input=0
  for _arg in "$@"; do
    if [ "$_method_next" = "1" ]; then
      _method="$_arg"
      _method_next=""
      if [ "$_arg" = "POST" ]; then
        _has_post=1
      fi
      continue
    fi
    case "$_arg" in
      --method) _method_next=1 ;;
      -) _has_input=1 ;;
    esac
  done

  if [ "$_has_post" = "1" ]; then
    # POST path: read stdin into payload file, extract target
    _state="${MOCK_GH_POST_STATE:-ok}"
    _seq=$(cat "$GH_PAYLOAD_SEQ")
    _seq=$((_seq + 1))
    echo "$_seq" > "$GH_PAYLOAD_SEQ"
    _payload_file="$BATS_TEST_TMPDIR/gh-payload-$_seq.json"
    if [ "$_has_input" = "1" ]; then
      cat > "$_payload_file"
    else
      : > "$_payload_file"
    fi
    # Extract target from payload
    _target="unknown"
    if grep -F -- '"target": "branch"' "$_payload_file" >/dev/null 2>&1; then
      _target="branch"
    elif grep -F -- '"target": "tag"' "$_payload_file" >/dev/null 2>&1; then
      _target="tag"
    fi
    case "$_state" in
      ok)
        printf 'gh\tapi\tPOST\t%s\t%s\t0\n' "$_argv_rest" "$_target" >> "$SHIM_CALLS_LOG"
        printf 'gh\tapi_payload\tPOST\t-\t%s\t%s\n' "$_target" "$_payload_file" >> "$SHIM_CALLS_LOG"
        exit 0
        ;;
      fail)
        echo "gh: HTTP 422 Unprocessable Entity" >&2
        printf 'gh\tapi\tPOST\t%s\t%s\t1\n' "$_argv_rest" "$_target" >> "$SHIM_CALLS_LOG"
        printf 'gh\tapi_payload\tPOST\t-\t%s\t%s\n' "$_target" "$_payload_file" >> "$SHIM_CALLS_LOG"
        exit 1
        ;;
    esac
  fi

  # GET path (list)
  _state="${MOCK_GH_LIST_STATE:-ok}"
  case "$_state" in
    ok)
      if [ -n "${MOCK_GH_RULESETS_NAMES:-}" ]; then
        printf '%s\n' "$MOCK_GH_RULESETS_NAMES"
      fi
      printf 'gh\tapi\tGET\t%s\t-\t0\n' "$_argv_rest" >> "$SHIM_CALLS_LOG"
      exit 0
      ;;
    fail)
      echo "gh: HTTP 500 Internal Server Error" >&2
      printf 'gh\tapi\tGET\t%s\t-\t1\n' "$_argv_rest" >> "$SHIM_CALLS_LOG"
      exit 1
      ;;
  esac
fi

echo "[shim] unknown gh invocation: $_argv" >&2
printf 'gh\tapi\t-\t%s\t-\t1\n' "$_argv" >> "$SHIM_CALLS_LOG"
exit 1
SHIM
}

_write_git_shim() {
  cat > "$BATS_TEST_TMPDIR/shim-bin/git" <<'SHIM'
#!/bin/sh
_argv="$*"
_sub1="${1:-}"
_sub2="${2:-}"

if [ "$_sub1" = "remote" ] && [ "$_sub2" = "get-url" ]; then
  _state="${MOCK_GIT_REMOTE_STATE:-ok}"
  case "$_state" in
    ok)
      printf '%s\n' "${MOCK_GIT_REMOTE_URL:-}"
      printf 'git\tremote\t-\t%s\t-\t0\n' "$_argv" >> "$SHIM_CALLS_LOG"
      exit 0
      ;;
    empty)
      printf 'git\tremote\t-\t%s\t-\t0\n' "$_argv" >> "$SHIM_CALLS_LOG"
      exit 0
      ;;
    fail)
      printf 'git\tremote\t-\t%s\t-\t1\n' "$_argv" >> "$SHIM_CALLS_LOG"
      exit 1
      ;;
  esac
fi

echo "[shim] unknown git subcommand: $_argv" >&2
printf 'git\tremote\t-\t%s\t-\t1\n' "$_argv" >> "$SHIM_CALLS_LOG"
exit 1
SHIM
}

# assert_gh_api_called <method> <path_substring> [<target>]
#   Match rows with command=gh, category=api, exact method, argv contains
#   path_substring (literal), and optionally target matches exactly.
assert_gh_api_called() {
  local _method="$1"
  local _sub="$2"
  local _target="${3:-}"
  while IFS=$'\t' read -r _c _cat _m _argv _t _last; do
    [ "$_c" = "gh" ] || continue
    [ "$_cat" = "api" ] || continue
    [ "$_m" = "$_method" ] || continue
    if [ -n "$_sub" ]; then
      printf '%s' "$_argv" | grep -F -- "$_sub" >/dev/null 2>&1 || continue
    fi
    if [ -n "$_target" ]; then
      [ "$_t" = "$_target" ] || continue
    fi
    return 0
  done < "$SHIM_CALLS_LOG"
  echo "assert_gh_api_called FAILED: method='$_method' sub='$_sub' target='$_target'" >&2
  echo "--- shim-calls.log ---" >&2
  cat "$SHIM_CALLS_LOG" >&2
  return 1
}

# assert_gh_api_not_called <method> <path_substring> [<target>]
assert_gh_api_not_called() {
  local _method="$1"
  local _sub="$2"
  local _target="${3:-}"
  while IFS=$'\t' read -r _c _cat _m _argv _t _last; do
    [ "$_c" = "gh" ] || continue
    [ "$_cat" = "api" ] || continue
    [ "$_m" = "$_method" ] || continue
    if [ -n "$_sub" ]; then
      printf '%s' "$_argv" | grep -F -- "$_sub" >/dev/null 2>&1 || continue
    fi
    if [ -n "$_target" ]; then
      [ "$_t" = "$_target" ] || continue
    fi
    echo "assert_gh_api_not_called FAILED: method='$_method' sub='$_sub' target='$_target' matched" >&2
    return 1
  done < "$SHIM_CALLS_LOG"
  return 0
}

# assert_gh_auth_called — gh auth status logged as category=api with argv starting with 'status'
assert_gh_auth_called() {
  while IFS=$'\t' read -r _c _cat _m _argv _t _last; do
    [ "$_c" = "gh" ] || continue
    [ "$_cat" = "api" ] || continue
    case "$_argv" in
      status*) return 0 ;;
    esac
  done < "$SHIM_CALLS_LOG"
  echo "assert_gh_auth_called FAILED: no 'gh auth status' row found" >&2
  echo "--- shim-calls.log ---" >&2
  cat "$SHIM_CALLS_LOG" >&2
  return 1
}

# assert_gh_auth_not_called
assert_gh_auth_not_called() {
  while IFS=$'\t' read -r _c _cat _m _argv _t _last; do
    [ "$_c" = "gh" ] || continue
    [ "$_cat" = "api" ] || continue
    case "$_argv" in
      status*)
        echo "assert_gh_auth_not_called FAILED: 'gh auth status' was called" >&2
        return 1
        ;;
    esac
  done < "$SHIM_CALLS_LOG"
  return 0
}

# assert_gh_post_called <target>
assert_gh_post_called() {
  assert_gh_api_called POST "rulesets" "$1"
}

# assert_gh_post_not_called <target>
assert_gh_post_not_called() {
  assert_gh_api_not_called POST "rulesets" "$1"
}

# assert_gh_payload_contains <target> <substring>
#   Find auxiliary rows with category=api_payload + matching target, then
#   grep -F the substring in the payload file recorded in `last` column.
assert_gh_payload_contains() {
  local _target="$1"
  local _sub="$2"
  local _matched=0
  while IFS=$'\t' read -r _c _cat _m _argv _t _last; do
    [ "$_c" = "gh" ] || continue
    [ "$_cat" = "api_payload" ] || continue
    [ "$_t" = "$_target" ] || continue
    if [ -f "$_last" ] && grep -F -- "$_sub" "$_last" >/dev/null 2>&1; then
      return 0
    fi
    _matched=1
  done < "$SHIM_CALLS_LOG"
  if [ "$_matched" = "1" ]; then
    echo "assert_gh_payload_contains FAILED: target='$_target' sub='$_sub' not found in any payload" >&2
  else
    echo "assert_gh_payload_contains FAILED: no api_payload row for target='$_target'" >&2
  fi
  echo "--- shim-calls.log ---" >&2
  cat "$SHIM_CALLS_LOG" >&2
  return 1
}

# ----------------------------------------------------------------
# Unit 003 (aws.bats) helpers — aws PATH shim + sysbin whitelist
#
# Spec: .aidlc/cycles/v0.3.1/design-artifacts/logical-designs/
#       unit_003_aws_bats_tests_logical_design.md
#
# PATH is strongly isolated to $BATS_TEST_TMPDIR/shim-bin:$BATS_TEST_TMPDIR/sysbin
# (no /usr/bin, no /bin). sysbin holds mandatory symlinks (12 commands: readlink
# dirname cat grep cut rm chmod mkdir touch awk tr sed; the last two are used
# for closed profile-name normalization in the aws shim) plus an optional jq
# symlink (present only if OS jq is available). The aws binary is NEVER added
# to sysbin to guarantee that real aws CLI is unreachable.
#
# shim-calls.log is a 6-column TSV:
#   command<TAB>category<TAB>method<TAB>argv<TAB>profile<TAB>exit_code
#
# Test flow: set pre-source env vars -> setup_aws_shims -> source lib/aws.sh
# (which touches $_tmpdir/aws-config and $_tmpdir/aws-credentials) -> run
# _setup_aws_credentials or call _write_aws_profile directly.
# ----------------------------------------------------------------

setup_aws_shims() {
  mkdir -p "$BATS_TEST_TMPDIR/shim-bin"
  mkdir -p "$BATS_TEST_TMPDIR/sysbin"
  mkdir -p "$BATS_TEST_TMPDIR/home"
  mkdir -p "$BATS_TEST_TMPDIR/aws-work"

  _aws_link_sysbin_whitelist || return 1
  _aws_link_jq_optional

  _write_aws_shim

  chmod +x "$BATS_TEST_TMPDIR/shim-bin"/*

  export PATH="$BATS_TEST_TMPDIR/shim-bin:$BATS_TEST_TMPDIR/sysbin"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export USER="jailrun-test"
  export HOME="$BATS_TEST_TMPDIR/home"
  export SHIM_CALLS_LOG="$BATS_TEST_TMPDIR/shim-calls.log"
  export _tmpdir="$BATS_TEST_TMPDIR/aws-work"

  : > "$SHIM_CALLS_LOG"
}

setup_aws_shims_without_jq() {
  setup_aws_shims || return 1
  rm -f "$BATS_TEST_TMPDIR/sysbin/jq"
}

teardown_aws_shims() {
  :
}

# Symlink required system binaries from /usr/bin (preferred) or /bin.
# aws must NEVER be in this whitelist. jq is handled separately (optional).
_aws_link_sysbin_whitelist() {
  local _cmd
  for _cmd in readlink dirname cat grep cut rm chmod mkdir touch awk tr sed; do
    if [ -x "/usr/bin/$_cmd" ]; then
      ln -sf "/usr/bin/$_cmd" "$BATS_TEST_TMPDIR/sysbin/$_cmd"
    elif [ -x "/bin/$_cmd" ]; then
      ln -sf "/bin/$_cmd" "$BATS_TEST_TMPDIR/sysbin/$_cmd"
    else
      echo "[setup_aws_shims] ERROR: required system binary $_cmd not found in /usr/bin or /bin" >&2
      return 1
    fi
  done
}

# Optional jq symlink: present iff OS jq is available. AW9 removes it to force
# the grep/cut fallback path in lib/aws.sh.
_aws_link_jq_optional() {
  local _jq_path
  _jq_path=$(command -v jq 2>/dev/null || true)
  if [ -n "$_jq_path" ] && [ -x "$_jq_path" ]; then
    ln -sf "$_jq_path" "$BATS_TEST_TMPDIR/sysbin/jq"
  fi
}

_write_aws_shim() {
  cat > "$BATS_TEST_TMPDIR/shim-bin/aws" <<'SHIM'
#!/bin/sh
# aws shim: handles `configure export-credentials` and `configure get region`.
# Controlled by MOCK_AWS_EXPORT_STATE_<KEY>, MOCK_AWS_EXPORT_JSON_<KEY>,
# MOCK_AWS_REGION_<KEY> where <KEY> is a normalized profile name.

_sub1="${1:-}"
_sub2="${2:-}"

# Extract --profile <value> from the full argv. If absent, KEY=DEFAULT.
_profile="-"
_prev=""
for _arg in "$@"; do
  if [ "$_prev" = "--profile" ]; then
    _profile="$_arg"
    break
  fi
  _prev="$_arg"
done

# Normalize profile name to a shell-variable-safe suffix [A-Z0-9_]:
#   [a-z] -> [A-Z], any non-[A-Z0-9_] -> _ (closed normalization).
if [ "$_profile" = "-" ]; then
  _key="DEFAULT"
else
  _key=$(printf '%s' "$_profile" | tr 'a-z' 'A-Z' | sed 's/[^A-Z0-9_]/_/g')
fi

# Build argv (space-joined) excluding $0; keep it tab-free for TSV integrity.
_argv=""
for _arg in "$@"; do
  if [ -z "$_argv" ]; then
    _argv="$_arg"
  else
    _argv="$_argv $_arg"
  fi
done

_log_row() {
  # command<TAB>category<TAB>method<TAB>argv<TAB>profile<TAB>exit_code
  printf 'aws\tconfigure\t%s\t%s\t%s\t%s\n' "$1" "$_argv" "$_profile" "$2" >> "$SHIM_CALLS_LOG"
}

case "$_sub1 $_sub2" in
  "configure export-credentials")
    _state_var="MOCK_AWS_EXPORT_STATE_${_key}"
    _json_var="MOCK_AWS_EXPORT_JSON_${_key}"
    eval "_state=\${$_state_var:-ok}"
    eval "_json=\${$_json_var:-}"
    case "$_state" in
      ok)
        if [ -n "$_json" ]; then
          printf '%s\n' "$_json"
        fi
        _log_row "export-credentials" 0
        exit 0
        ;;
      fail)
        echo "Unable to locate credentials. You can configure credentials by running \"aws configure\"." >&2
        _log_row "export-credentials" 255
        exit 255
        ;;
    esac
    ;;
  "configure get")
    if [ "$3" = "region" ]; then
      _region_var="MOCK_AWS_REGION_${_key}"
      eval "_region=\${$_region_var:-}"
      if [ -n "$_region" ]; then
        printf '%s\n' "$_region"
        _log_row "get-region" 0
        exit 0
      fi
      _log_row "get-region" 1
      exit 1
    fi
    ;;
esac

echo "[shim] unknown aws subcommand: $_argv" >&2
_log_row "unknown" 1
exit 1
SHIM
}

# assert_aws_configure_called <method> <profile>
#   method: export-credentials | get-region | unknown
#   profile: profile name (e.g. default / work) or - for absent
assert_aws_configure_called() {
  local _method="$1"
  local _profile="$2"
  while IFS=$'\t' read -r _c _cat _m _argv _p _ec; do
    [ "$_c" = "aws" ] || continue
    [ "$_cat" = "configure" ] || continue
    [ "$_m" = "$_method" ] || continue
    [ "$_p" = "$_profile" ] || continue
    return 0
  done < "$SHIM_CALLS_LOG"
  echo "assert_aws_configure_called FAILED: method='$_method' profile='$_profile'" >&2
  echo "--- shim-calls.log ---" >&2
  cat "$SHIM_CALLS_LOG" >&2
  return 1
}

assert_aws_configure_not_called() {
  local _method="$1"
  local _profile="$2"
  while IFS=$'\t' read -r _c _cat _m _argv _p _ec; do
    [ "$_c" = "aws" ] || continue
    [ "$_cat" = "configure" ] || continue
    [ "$_m" = "$_method" ] || continue
    [ "$_p" = "$_profile" ] || continue
    echo "assert_aws_configure_not_called FAILED: method='$_method' profile='$_profile'" >&2
    return 1
  done < "$SHIM_CALLS_LOG"
  return 0
}

# --- INI assertion helpers ---------------------------------------------------
# Section matching uses awk with a -v variable bound to the section name so that
# regex metacharacters (., -, /) in profile names never cause false matches.
# Same design for both $_aws_config and $_aws_creds.

_aws_ini_file_for_kind() {
  # $1: config|creds
  case "$1" in
    config) printf '%s' "$_aws_config" ;;
    creds)  printf '%s' "$_aws_creds" ;;
    *)      return 1 ;;
  esac
}

# _aws_assert_section_count <kind> <section> <expected_count>
_aws_assert_section_count() {
  local _kind="$1" _section="$2" _expected="$3"
  local _file
  _file=$(_aws_ini_file_for_kind "$_kind") || return 1
  local _actual
  _actual=$(awk -v sec="$_section" 'BEGIN{n=0} { if ($0 == "[" sec "]") n++ } END{print n}' "$_file")
  if [ "$_actual" = "$_expected" ]; then
    return 0
  fi
  echo "assert_aws_${_kind}_section_count FAILED: section='$_section' expected=$_expected actual=$_actual" >&2
  echo "--- $_kind file ($_file) ---" >&2
  cat "$_file" >&2
  return 1
}

# _aws_assert_section_exists <kind> <section>
_aws_assert_section_exists() {
  local _kind="$1" _section="$2"
  local _file
  _file=$(_aws_ini_file_for_kind "$_kind") || return 1
  if awk -v sec="$_section" '$0 == "[" sec "]" { found=1 } END { exit (found ? 0 : 1) }' "$_file"; then
    return 0
  fi
  echo "assert_aws_${_kind}_section FAILED: section='$_section' not found" >&2
  echo "--- $_kind file ($_file) ---" >&2
  cat "$_file" >&2
  return 1
}

# _aws_assert_section_not_exists <kind> <section>
_aws_assert_section_not_exists() {
  local _kind="$1" _section="$2"
  local _file
  _file=$(_aws_ini_file_for_kind "$_kind") || return 1
  if awk -v sec="$_section" '$0 == "[" sec "]" { found=1 } END { exit (found ? 0 : 1) }' "$_file"; then
    echo "assert_aws_${_kind}_section_not_exists FAILED: section='$_section' was found" >&2
    echo "--- $_kind file ($_file) ---" >&2
    cat "$_file" >&2
    return 1
  fi
  return 0
}

# _aws_assert_section_order <kind> <section_1> [<section_2> ...]
#   Requires the sections in the file appear in the given order. Duplicate names
#   are treated as separate positions.
_aws_assert_section_order() {
  local _kind="$1"
  shift
  local _file
  _file=$(_aws_ini_file_for_kind "$_kind") || return 1
  local _actual
  _actual=$(awk 'match($0, /^\[.*\]$/) { print substr($0, RSTART+1, RLENGTH-2) }' "$_file" | tr '\n' '|')
  local _expected=""
  local _s
  for _s in "$@"; do
    _expected="${_expected}${_s}|"
  done
  if [ "$_actual" = "$_expected" ]; then
    return 0
  fi
  echo "assert_aws_${_kind}_section_order FAILED: expected='$_expected' actual='$_actual'" >&2
  echo "--- $_kind file ($_file) ---" >&2
  cat "$_file" >&2
  return 1
}

# _aws_assert_line <kind> <section> <key> <value>
#   Succeeds if ANY [section] block contains '<key> = <value>'.
_aws_assert_line() {
  local _kind="$1" _section="$2" _key="$3" _value="$4"
  local _file
  _file=$(_aws_ini_file_for_kind "$_kind") || return 1
  local _needle="$_key = $_value"
  if awk -v sec="$_section" -v needle="$_needle" '
    BEGIN { in_sec = 0 }
    $0 == "[" sec "]" { in_sec = 1; next }
    /^\[.*\]$/ { in_sec = 0; next }
    in_sec && $0 == needle { print "match"; exit }
  ' "$_file" | grep -q match; then
    return 0
  fi
  echo "assert_aws_${_kind}_line FAILED: section='$_section' key='$_key' value='$_value'" >&2
  echo "--- $_kind file ($_file) ---" >&2
  cat "$_file" >&2
  return 1
}

# _aws_assert_line_in_nth <kind> <section> <nth> <key> <value>
#   Succeeds if the <nth> (1-origin) [section] block contains '<key> = <value>'.
_aws_assert_line_in_nth() {
  local _kind="$1" _section="$2" _nth="$3" _key="$4" _value="$5"
  local _file
  _file=$(_aws_ini_file_for_kind "$_kind") || return 1
  local _needle="$_key = $_value"
  if awk -v sec="$_section" -v needle="$_needle" -v target="$_nth" '
    BEGIN { seen = 0; in_sec = 0 }
    $0 == "[" sec "]" { seen++; in_sec = (seen == target) ? 1 : 0; next }
    /^\[.*\]$/ { in_sec = 0; next }
    in_sec && $0 == needle { print "match"; exit }
  ' "$_file" | grep -q match; then
    return 0
  fi
  echo "assert_aws_${_kind}_line_in_nth FAILED: section='$_section' nth=$_nth key='$_key' value='$_value'" >&2
  echo "--- $_kind file ($_file) ---" >&2
  cat "$_file" >&2
  return 1
}

# assert_aws_creds_line_absent <section> <key>
#   Succeeds if NO [section] block contains a line starting with '<key>'.
#   (Used to verify aws_session_token is omitted when empty.)
assert_aws_creds_line_absent() {
  local _section="$1" _key="$2"
  local _file="$_aws_creds"
  if awk -v sec="$_section" -v key="$_key" '
    BEGIN { in_sec = 0 }
    $0 == "[" sec "]" { in_sec = 1; next }
    /^\[.*\]$/ { in_sec = 0; next }
    in_sec {
      idx = index($0, key " = ")
      if (idx == 1) { print "match"; exit }
    }
  ' "$_file" | grep -q match; then
    echo "assert_aws_creds_line_absent FAILED: section='$_section' key='$_key' was found" >&2
    echo "--- creds file ($_file) ---" >&2
    cat "$_file" >&2
    return 1
  fi
  return 0
}

# Public wrappers for config side
assert_aws_config_section()            { _aws_assert_section_exists config "$1"; }
assert_aws_config_section_not_exists() { _aws_assert_section_not_exists config "$1"; }
assert_aws_config_section_count()      { _aws_assert_section_count config "$1" "$2"; }
assert_aws_config_section_order()      { _aws_assert_section_order config "$@"; }
assert_aws_config_line()               { _aws_assert_line config "$1" "$2" "$3"; }
assert_aws_config_line_in_nth()        { _aws_assert_line_in_nth config "$1" "$2" "$3" "$4"; }

# Public wrappers for creds side
assert_aws_creds_section()            { _aws_assert_section_exists creds "$1"; }
assert_aws_creds_section_not_exists() { _aws_assert_section_not_exists creds "$1"; }
assert_aws_creds_section_count()      { _aws_assert_section_count creds "$1" "$2"; }
assert_aws_creds_section_order()      { _aws_assert_section_order creds "$@"; }
assert_aws_creds_line()               { _aws_assert_line creds "$1" "$2" "$3"; }
assert_aws_creds_line_in_nth()        { _aws_assert_line_in_nth creds "$1" "$2" "$3" "$4"; }
