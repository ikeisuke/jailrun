#!/usr/bin/env bats
#
# Unit 002 (secret-inject-runtime) tests for lib/sandbox.sh.
#
# Design SoT:
#   .aidlc/cycles/v0.7.0/design-artifacts/logical-designs/
#       unit_002_secret_inject_runtime_logical_design.md (テスト設計)
#
# Strategy: source config.sh / credentials.sh / sandbox.sh, then override
# `_get_token` (real def comes from token.sh which sandbox.sh sources) and
# set `_gh_token` AFTER sourcing — credentials.sh resets `_gh_token` at source
# time, so a pre-set value would be overwritten. SANDBOX_SECRET_INJECT is set
# directly (config-driven in production; here we drive _resolve_secret_inject
# in isolation). Warnings (stderr) are captured to a file for masking checks.

load helpers

setup() {
  setup_jailrun_env
  TEST_CONFIG_DIR=$(mktemp -d)
  export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config.toml" <<CONF
[global]
allowed_aws_profiles = []
default_aws_profile = ""
gh_token_name = "classic"
CONF
}

teardown() {
  rm -rf "$TEST_CONFIG_DIR"
}

# Build and run a harness:
#   $1 = SANDBOX_SECRET_INJECT value
#   $2 = _gh_token value (set after source; empty string = no existing token)
#   $3 = _get_token stub `case` arms (e.g. 'jailrun:FOO:ok) printf "%s" v ;;')
# Output (combined): RC=<n>, ===ENVSPEC=== <env-spec>, ===WARNS=== <stderr>
run_si() {
  local si="$1" ghtok="$2" stub="$3"
  local h="$TEST_CONFIG_DIR/harness.sh"
  cat > "$h" <<HARNESS
export JAILRUN_LIB="$JAILRUN_LIB"
export WRAPPER_NAME=claude
export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
. "\$JAILRUN_LIB/config.sh" >/dev/null 2>&1
. "\$JAILRUN_LIB/credentials.sh" 2>/dev/null
. "\$JAILRUN_LIB/sandbox.sh"
_get_token() {
  case "\$1" in
    $stub
    *) : ;;
  esac
}
_gh_token="$ghtok"
SANDBOX_SECRET_INJECT="$si"
# sandbox.sh sources token.sh which enables \`set -eu\`; use an if-condition so a
# duplicate-env abort (return 1) does not kill the harness before we report RC.
if _build_env_spec 2>"$TEST_CONFIG_DIR/warns"; then _rc=0; else _rc=\$?; fi
echo "RC=\$_rc"
echo "VALFILE=\$([ -f "\$_tmpdir/secret-inject-val" ] && echo present || echo absent)"
echo "===ENVSPEC==="
[ -f "\$_tmpdir/env-spec" ] && cat "\$_tmpdir/env-spec"
echo "===WARNS==="
cat "$TEST_CONFIG_DIR/warns"
HARNESS
  run env -u _CREDENTIAL_GUARD_SANDBOXED sh "$h"
}

# --- 1: general injection success ---
@test "secret-inject injects a registered general variable" {
  run_si "FOO:ok" "" 'jailrun:FOO:ok) printf "%s" "sekret-foo" ;;'
  [ "$status" -eq 0 ]
  [[ "$output" == *"RC=0"* ]]
  [[ "$output" == *"SET FOO=sekret-foo"* ]]
}

# --- 2: unregistered identifier -> warn + skip, continue ---
@test "secret-inject skips unregistered identifier and continues" {
  run_si "FOO:missing" "" ''
  [ "$status" -eq 0 ]
  [[ "$output" == *"RC=0"* ]]
  [[ "$output" != *"SET FOO="* ]]
  [[ "$output" == *"identifier not found in keychain"* ]]
}

# --- 3-7: syntax-invalid entries -> warn + skip ---
@test "secret-inject skips invalid entry: missing colon (FOO)" {
  run_si "FOO" "" ''
  [ "$status" -eq 0 ]
  [[ "$output" != *"SET FOO="* ]]
  [[ "$output" == *"missing ':'"* ]]
}

@test "secret-inject skips invalid entry: empty identifier (FOO:)" {
  run_si "FOO:" "" ''
  [ "$status" -eq 0 ]
  [[ "$output" != *"SET FOO="* ]]
  [[ "$output" == *"empty identifier"* ]]
}

@test "secret-inject skips invalid entry: empty env (:id)" {
  run_si ":id" "" ''
  [ "$status" -eq 0 ]
  [[ "$output" == *"invalid env name"* ]]
}

@test "secret-inject skips invalid entry: lowercase env (foo:id)" {
  run_si "foo:id" "" 'jailrun:foo:id) printf "%s" "should-not-appear" ;;'
  [ "$status" -eq 0 ]
  [[ "$output" != *"SET foo="* ]]
  [[ "$output" != *"should-not-appear"* ]]
  [[ "$output" == *"invalid env name"* ]]
}

@test "secret-inject skips invalid entry: multiple colons (FOO:a:b)" {
  run_si "FOO:a:b" "" 'jailrun:FOO:a:b) printf "%s" "should-not-appear" ;;'
  [ "$status" -eq 0 ]
  [[ "$output" != *"SET FOO="* ]]
  [[ "$output" == *"identifier contains ':'"* ]]
}

# --- 8: duplicate env -> abort (non-zero, env-spec not generated) ---
@test "secret-inject aborts on duplicate env declaration" {
  run_si "FOO:a FOO:b" "" 'jailrun:FOO:a) printf "%s" "va" ;; jailrun:FOO:b) printf "%s" "vb" ;;'
  [ "$status" -eq 0 ]   # harness itself exits 0 (RC captured via if-condition)
  # _build_env_spec returns non-zero -> caller aborts (under set -e in production)
  [[ "$output" == *"RC=1"* ]]
  [[ "$output" == *"duplicate env in SANDBOX_SECRET_INJECT: FOO"* ]]
  # env-spec must not be generated on abort (no SET lines emitted)
  [[ "$output" != *"SET FOO="* ]]
}

# --- 9: general reserved name -> warn + allow (override) ---
@test "secret-inject warns but allows a general reserved name (PATH)" {
  run_si "PATH:x" "" 'jailrun:PATH:x) printf "%s" "/custom/bin" ;;'
  [ "$status" -eq 0 ]
  [[ "$output" == *"overriding reserved variable via SANDBOX_SECRET_INJECT: PATH"* ]]
  [[ "$output" == *"SET PATH=/custom/bin"* ]]
}

# --- 10-11: non-reserved wildcards must NOT be treated as reserved ---
@test "secret-inject does not reserve SANDBOX_* names" {
  run_si "SANDBOX_FOO:x" "" 'jailrun:SANDBOX_FOO:x) printf "%s" "sval" ;;'
  [ "$status" -eq 0 ]
  [[ "$output" != *"reserved variable"* ]]
  [[ "$output" == *"SET SANDBOX_FOO=sval"* ]]
}

@test "secret-inject does not reserve AWS_* names beyond the explicit set" {
  run_si "AWS_FOO:x" "" 'jailrun:AWS_FOO:x) printf "%s" "aval" ;;'
  [ "$status" -eq 0 ]
  [[ "$output" != *"reserved variable"* ]]
  [[ "$output" == *"SET AWS_FOO=aval"* ]]
}

# --- 12: newline value (LF) -> warn + skip ---
@test "secret-inject skips a value containing a newline (LF)" {
  run_si "FOO:nl" "" 'jailrun:FOO:nl) printf "line1\nline2" ;;'
  [ "$status" -eq 0 ]
  [[ "$output" != *"SET FOO="* ]]
  [[ "$output" == *"value contains newlines"* ]]
}

@test "secret-inject skips a value containing a carriage return (CR)" {
  run_si "FOO:cr" "" 'jailrun:FOO:cr) printf "line1\rline2" ;;'
  [ "$status" -eq 0 ]
  [[ "$output" != *"SET FOO="* ]]
  [[ "$output" == *"value contains newlines"* ]]
}

@test "secret-inject skips a value with only a trailing newline (LF)" {
  # command substitution strips trailing LFs; this guards the file-based check
  run_si "FOO:trail" "" 'jailrun:FOO:trail) printf "secret\n" ;;'
  [ "$status" -eq 0 ]
  [[ "$output" != *"SET FOO="* ]]
  [[ "$output" == *"value contains newlines"* ]]
}

@test "secret-inject skips a value with only a trailing carriage return (CR)" {
  run_si "FOO:trailcr" "" 'jailrun:FOO:trailcr) printf "secret\r" ;;'
  [ "$status" -eq 0 ]
  [[ "$output" != *"SET FOO="* ]]
  [[ "$output" == *"value contains newlines"* ]]
}

# --- 13: GH_TOKEN success last-wins (suppress existing SET, warn, git-askpass) ---
@test "secret-inject GH_TOKEN success suppresses existing SET and wins" {
  run_si "GH_TOKEN:work" "existing-gh-token" 'jailrun:GH_TOKEN:work) printf "%s" "secret-gh-token" ;;'
  [ "$status" -eq 0 ]
  [[ "$output" == *"SET GH_TOKEN=secret-gh-token"* ]]
  [[ "$output" != *"SET GH_TOKEN=existing-gh-token"* ]]
  [[ "$output" == *"SET GIT_ASKPASS="* ]]
  [[ "$output" == *"overriding existing GH_TOKEN handling via SANDBOX_SECRET_INJECT"* ]]
}

# --- 14-16: GH_TOKEN declared-but-skipped -> fallback to existing, no suppression ---
@test "secret-inject GH_TOKEN skip (unregistered) falls back to existing token" {
  run_si "GH_TOKEN:missing" "existing-gh-token" ''
  [ "$status" -eq 0 ]
  [[ "$output" == *"SET GH_TOKEN=existing-gh-token"* ]]
  [[ "$output" == *"SET GIT_ASKPASS="* ]]
  [[ "$output" == *"identifier not found in keychain"* ]]
  [[ "$output" != *"overriding existing GH_TOKEN handling"* ]]
}

@test "secret-inject GH_TOKEN skip (newline) falls back to existing token" {
  run_si "GH_TOKEN:nl" "existing-gh-token" 'jailrun:GH_TOKEN:nl) printf "a\nb" ;;'
  [ "$status" -eq 0 ]
  [[ "$output" == *"SET GH_TOKEN=existing-gh-token"* ]]
  [[ "$output" == *"SET GIT_ASKPASS="* ]]
  [[ "$output" == *"value contains newlines"* ]]
  [[ "$output" != *"overriding existing GH_TOKEN handling"* ]]
}

@test "secret-inject GH_TOKEN skip (syntax invalid) falls back to existing token" {
  run_si "GH_TOKEN:a:b" "existing-gh-token" ''
  [ "$status" -eq 0 ]
  [[ "$output" == *"SET GH_TOKEN=existing-gh-token"* ]]
  [[ "$output" == *"SET GIT_ASKPASS="* ]]
  [[ "$output" == *"identifier contains ':'"* ]]
  [[ "$output" != *"overriding existing GH_TOKEN handling"* ]]
}

# --- 17: GH_TOKEN supplied via secret-inject only (no existing token) ---
@test "secret-inject GH_TOKEN-only supply sets git-askpass end-to-end" {
  run_si "GH_TOKEN:work" "" 'jailrun:GH_TOKEN:work) printf "%s" "secret-only-token" ;;'
  [ "$status" -eq 0 ]
  [[ "$output" == *"SET GH_TOKEN=secret-only-token"* ]]
  [[ "$output" == *"SET GIT_ASKPASS="* ]]
  [[ "$output" == *"overriding existing GH_TOKEN handling via SANDBOX_SECRET_INJECT"* ]]
}

# --- 18: regression: no secret-inject + existing token -> unchanged ---
@test "no secret-inject keeps existing GH_TOKEN behaviour" {
  run_si "" "existing-gh-token" ''
  [ "$status" -eq 0 ]
  [[ "$output" == *"SET GH_TOKEN=existing-gh-token"* ]]
  [[ "$output" == *"SET GIT_ASKPASS="* ]]
}

@test "no secret-inject + no existing token emits no GH_TOKEN/git-askpass" {
  run_si "" "" ''
  [ "$status" -eq 0 ]
  [[ "$output" != *"SET GH_TOKEN="* ]]
  [[ "$output" != *"SET GIT_ASKPASS="* ]]
}

# --- 19: secret value masking (skipped value must not leak to warns) ---
@test "secret-inject does not leak a skipped secret value into warnings" {
  run_si "FOO:nl" "" 'jailrun:FOO:nl) printf "TOPSECRETxyz\ntail" ;;'
  [ "$status" -eq 0 ]
  # value is skipped, so it must appear neither in env-spec nor in warns
  [[ "$output" != *"TOPSECRETxyz"* ]]
  [[ "$output" == *"value contains newlines"* ]]
  # the raw secret temp file must not persist after a skip
  [[ "$output" == *"VALFILE=absent"* ]]
}

@test "secret-inject removes the raw secret temp file after injection" {
  run_si "FOO:ok" "" 'jailrun:FOO:ok) printf "%s" "vfoo" ;;'
  [ "$status" -eq 0 ]
  [[ "$output" == *"SET FOO=vfoo"* ]]
  [[ "$output" == *"VALFILE=absent"* ]]
}

# --- 20: multiple entries, mixed outcomes in one pass ---
@test "secret-inject handles multiple entries in one pass" {
  run_si "FOO:ok BAR:missing BAZ:ok" "" 'jailrun:FOO:ok) printf "%s" "vfoo" ;; jailrun:BAZ:ok) printf "%s" "vbaz" ;;'
  [ "$status" -eq 0 ]
  [[ "$output" == *"SET FOO=vfoo"* ]]
  [[ "$output" == *"SET BAZ=vbaz"* ]]
  [[ "$output" != *"SET BAR="* ]]
  [[ "$output" == *"BAR (identifier not found in keychain)"* ]]
}

# --- 21: escaping is applied to injected secret values ---
@test "secret-inject escapes shell metacharacters in the value" {
  run_si 'FOO:meta' "" 'jailrun:FOO:meta) printf "%s" "a\$b\"c\\d" ;;'
  [ "$status" -eq 0 ]
  # _esc_env_value neutralises $, ", \  -> backslash-escaped in env-spec
  [[ "$output" == *'SET FOO=a\$b\"c\\d'* ]]
}
