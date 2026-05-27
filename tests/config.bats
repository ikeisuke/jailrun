#!/usr/bin/env bats

load helpers

setup() {
  setup_jailrun_env
  export _CREDENTIAL_GUARD_SANDBOXED=""
  unset AWS_PROFILE
  unset GH_TOKEN_NAME
  TEST_CONFIG_DIR=$(mktemp -d)
  export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
}

teardown() {
  rm -rf "$TEST_CONFIG_DIR"
}

@test "config.sh generates TOML config on first run" {
  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
  '
  # exits 1 and creates config
  [ "$status" -eq 1 ]
  [ -f "$TEST_CONFIG_DIR/jailrun/config.toml" ]
  grep -q "allowed_aws_profiles" "$TEST_CONFIG_DIR/jailrun/config.toml"
  grep -q "gh_token_name" "$TEST_CONFIG_DIR/jailrun/config.toml"
}

@test "config.sh loads existing TOML config" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config.toml" <<'EOF'
[global]
allowed_aws_profiles = ["testprofile"]
default_aws_profile = "testprofile"
gh_token_name = "test"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    echo "profiles=$ALLOWED_AWS_PROFILES"
    echo "default=$DEFAULT_AWS_PROFILE"
    echo "gh=$GH_TOKEN_NAME"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"profiles=testprofile"* ]]
  [[ "$output" == *"default=testprofile"* ]]
  [[ "$output" == *"gh=test"* ]]
}

@test "config.sh auto-migrates legacy shell config to TOML" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config" <<'EOF'
ALLOWED_AWS_PROFILES="migrated"
DEFAULT_AWS_PROFILE="default"
GH_TOKEN_NAME="classic"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    echo "profiles=$ALLOWED_AWS_PROFILES"
  '
  [ "$status" -eq 0 ]
  [ -f "$TEST_CONFIG_DIR/jailrun/config.toml" ]
  [[ "$output" == *"profiles=migrated"* ]]
}

@test "config.sh GH_TOKEN_NAME env override takes precedence" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config.toml" <<'EOF'
[global]
gh_token_name = "from-config"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    export GH_TOKEN_NAME="from-env"
    . "'"$JAILRUN_LIB"'/config.sh"
    echo "gh=$GH_TOKEN_NAME"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh=from-env"* ]]
}

@test "config.sh migrates from old security-wrapper dir" {
  mkdir -p "$TEST_CONFIG_DIR/security-wrapper"
  cat > "$TEST_CONFIG_DIR/security-wrapper/config" <<'EOF'
ALLOWED_AWS_PROFILES="migrated"
DEFAULT_AWS_PROFILE="default"
GH_TOKEN_NAME="classic"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    echo "profiles=$ALLOWED_AWS_PROFILES"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"profiles=migrated"* ]]
}

# ---------------------------------------------------------------------------
# Unit 003 (Issue #48): eval を排除した key=value envelope のラウンドトリップ
#   ケース (i)〜(vi): 通常値 / シェル特殊文字 / 中間改行 / 空値 / 未設定キー /
#                    後方互換（既存の絶対パス + COMMON マージ）
#
# 値域前提（ShellSafeString）: NUL 不可・末尾改行不保持。中間改行のみテスト対象。
# ---------------------------------------------------------------------------

# (i) 通常値: 既存 5 ケースで実質カバー済（プロファイル名 / トークン名）。
#     念のため `default_region` も含めて新フォーマットで loadable なことを再確認。
@test "config.sh (i) loads plain values via new key=value envelope" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config.toml" <<'EOF'
[global]
default_region = "us-west-2"
gh_token_name = "plain"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    echo "region=$DEFAULT_REGION"
    echo "gh=$GH_TOKEN_NAME"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"region=us-west-2"* ]]
  [[ "$output" == *"gh=plain"* ]]
}

# (ii) シェル特殊文字: $ / ` / " / ' / ; を含む値が eval されず正しく入る。
@test "config.sh (ii) preserves shell-meta characters in values (no eval)" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config.toml" <<'EOF'
[global]
default_region = "abc$(whoami)`uname`\";rm-rf;\""
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    printf "region=%s\n" "$DEFAULT_REGION"
  '
  [ "$status" -eq 0 ]
  # The literal string must be preserved verbatim (no command substitution).
  [[ "$output" == *'region=abc$(whoami)`uname`";rm-rf;"'* ]]
}

# (iii) 中間改行: 値中の改行はエスケープ → デコードで実改行に戻る。
@test "config.sh (iii) round-trips an embedded LF in a value" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  # TOML triple-quoted basic string so the value contains a literal LF.
  cat > "$TEST_CONFIG_DIR/jailrun/config.toml" <<'EOF'
[global]
default_region = """line1
line2"""
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    # Use printf %s so the LF survives the assertion.
    printf "%s" "$DEFAULT_REGION"
  '
  [ "$status" -eq 0 ]
  expected=$'line1\nline2'
  [ "$output" = "$expected" ]
}

# (iv) 空値: 空文字列を持つキーが env に空で入る。
@test "config.sh (iv) handles empty-string values" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config.toml" <<'EOF'
[global]
default_region = ""
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    # NB: config.sh has a post-load override that re-defaults _DEFAULT_REGION
    #     when DEFAULT_REGION is unset, but here DEFAULT_REGION is set to "".
    printf "region=[%s]\n" "$DEFAULT_REGION"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"region=[]"* ]]
}

# (v) 未設定キー: TOML に未記載のキーは export されず、後の参照で空のまま。
@test "config.sh (v) leaves unrelated keys unexported" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config.toml" <<'EOF'
[global]
gh_token_name = "x"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    unset SANDBOX_DENY_READ_NAMES
    . "'"$JAILRUN_LIB"'/config.sh"
    printf "sdr=[%s]\n" "$SANDBOX_DENY_READ_NAMES"
  '
  [ "$status" -eq 0 ]
  # DEFAULTS in config.py exports SANDBOX_DENY_READ_NAMES as "" (empty list).
  [[ "$output" == *"sdr=[]"* ]]
}

# (vi) 後方互換: 既存の絶対パス [dir."..."] と proxy_enabled の COMMON マージは
#      従来どおり動作する（Unit 003 のリファクタによる回帰なし）。
@test "config.sh (vi) preserves absolute-path dir match and proxy COMMON merge" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config.toml" <<'EOF'
[global]
proxy_enabled = true

[dir."/tmp/legacy/proj"]
sandbox_extra_allow_write = ["LEGACY"]
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    cd /tmp/legacy/proj 2>/dev/null || mkdir -p /tmp/legacy/proj && cd /tmp/legacy/proj
    . "'"$JAILRUN_LIB"'/config.sh"
    printf "extra=%s\n" "$SANDBOX_EXTRA_ALLOW_WRITE"
    printf "domains=%s\n" "$PROXY_ALLOW_DOMAINS"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"extra=LEGACY"* ]]
  # COMMON entries must be merged (Issue #99 / Unit 001 contract preserved).
  [[ "$output" == *"github.com"* ]]
  [[ "$output" == *"registry.npmjs.org"* ]]
}
