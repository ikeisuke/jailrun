#!/usr/bin/env bats
#
# Tests for `jailrun ruleset` subcommand (lib/ruleset.sh).
# PATH shims (gh / git) plus a sysbin whitelist directory are defined
# in tests/helpers.bash. Per-test behavior is controlled via MOCK_* env vars.
#
# Test case IDs correspond to:
#   .aidlc/cycles/v0.3.1/plans/unit-002-plan.md#テストケース設計
#
# Design refs:
#   .aidlc/cycles/v0.3.1/design-artifacts/domain-models/
#     unit_002_ruleset_bats_tests_domain_model.md
#   .aidlc/cycles/v0.3.1/design-artifacts/logical-designs/
#     unit_002_ruleset_bats_tests_logical_design.md

load helpers

setup() {
  setup_jailrun_env
  setup_ruleset_shims
}

teardown() {
  teardown_ruleset_shims
}

_jailrun_ruleset() {
  "$JAILRUN_DIR/jailrun" ruleset "$@"
}

# ========================================================================
# 1. 主要シナリオ（apply / skip / 失敗）
# ========================================================================

@test "RSB1 ruleset: branch/tag both new (POST called, payload partial match)" {
  export MOCK_GH_AUTH_STATE=ok
  export MOCK_GH_LIST_STATE=ok
  export MOCK_GH_RULESETS_NAMES=""
  export MOCK_GH_POST_STATE=ok
  run _jailrun_ruleset owner/repo
  [ "$status" -eq 0 ]
  assert_gh_auth_called
  assert_gh_post_called branch
  assert_gh_post_called tag
  assert_gh_payload_contains branch '"target": "branch"'
  assert_gh_payload_contains branch '"required_approving_review_count": 1'
  assert_gh_payload_contains tag '"target": "tag"'
  assert_gh_payload_contains tag '"include": ["~ALL"]'
}

@test "RSB2 ruleset: branch existing skip, tag apply" {
  export MOCK_GH_AUTH_STATE=ok
  export MOCK_GH_LIST_STATE=ok
  export MOCK_GH_RULESETS_NAMES="jailrun-branch-protection"
  export MOCK_GH_POST_STATE=ok
  run _jailrun_ruleset owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists, skipping"* ]]
  assert_gh_post_not_called branch
  assert_gh_post_called tag
}

@test "RST2 ruleset: tag existing skip, branch apply" {
  export MOCK_GH_AUTH_STATE=ok
  export MOCK_GH_LIST_STATE=ok
  export MOCK_GH_RULESETS_NAMES="jailrun-tag-protection"
  export MOCK_GH_POST_STATE=ok
  run _jailrun_ruleset owner/repo
  [ "$status" -eq 0 ]
  assert_gh_post_called branch
  assert_gh_post_not_called tag
}

@test "RSB3 ruleset: both existing, POST not called" {
  export MOCK_GH_AUTH_STATE=ok
  export MOCK_GH_LIST_STATE=ok
  export MOCK_GH_RULESETS_NAMES=$'jailrun-branch-protection\njailrun-tag-protection'
  export MOCK_GH_POST_STATE=ok
  run _jailrun_ruleset owner/repo
  [ "$status" -eq 0 ]
  assert_gh_post_not_called branch
  assert_gh_post_not_called tag
}

@test "RSF1 ruleset: branch POST failure exits non-zero (tag POST failure represented)" {
  export MOCK_GH_AUTH_STATE=ok
  export MOCK_GH_LIST_STATE=ok
  export MOCK_GH_RULESETS_NAMES=""
  export MOCK_GH_POST_STATE=fail
  run _jailrun_ruleset owner/repo
  [ "$status" -ne 0 ]
  # branch POST 呼び出し記録はあり (失敗ログ)
  assert_gh_post_called branch
}

@test "RSF2 ruleset: POST fires on list API failure (spec clarification)" {
  export MOCK_GH_AUTH_STATE=ok
  export MOCK_GH_LIST_STATE=fail
  export MOCK_GH_POST_STATE=ok
  run _jailrun_ruleset owner/repo
  # _ruleset_exists は || true で非 0 を吸収 → 「存在しない」扱いで POST 発火
  [ "$status" -eq 0 ]
  assert_gh_post_called branch
  assert_gh_post_called tag
}

# ========================================================================
# 2. 認証・環境ガード
# ========================================================================

@test "RSG1 ruleset: gh CLI not installed (PATH isolation deterministic)" {
  # shim-bin/gh を削除。PATH は shim-bin:sysbin のみ (sysbin に gh なし、
  # /usr/bin や /bin も PATH 外) のため、実環境 gh への fallthrough なし
  rm "$BATS_TEST_TMPDIR/shim-bin/gh"
  run _jailrun_ruleset owner/repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh CLI is not installed"* ]]
  assert_gh_auth_not_called
}

@test "RSG2 ruleset: gh not authenticated (auth status fail)" {
  export MOCK_GH_AUTH_STATE=fail
  run _jailrun_ruleset owner/repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh CLI is not authenticated"* ]]
  assert_gh_auth_called
  assert_gh_api_not_called GET "rulesets"
  assert_gh_post_not_called branch
  assert_gh_post_not_called tag
}

@test "RSG3 ruleset: --dry-run skips auth/list/POST" {
  # dry-run は auth check をスキップするため MOCK_GH_AUTH_STATE=fail でも通る
  export MOCK_GH_AUTH_STATE=fail
  run _jailrun_ruleset --dry-run owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"(dry-run) would create with:"* ]]
  assert_gh_auth_not_called
  assert_gh_api_not_called GET "rulesets"
  assert_gh_post_not_called branch
  assert_gh_post_not_called tag
}

# ========================================================================
# 3. 引数パース
# ========================================================================

@test "RSO1 ruleset: --help shows usage" {
  run _jailrun_ruleset --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: jailrun ruleset"* ]]
  assert_gh_auth_not_called
}

@test "RSO1b ruleset: -h shows usage" {
  run _jailrun_ruleset -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: jailrun ruleset"* ]]
  assert_gh_auth_not_called
}

@test "RSO2 ruleset: unknown option exits 1" {
  run _jailrun_ruleset --unknown
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "RSO3 ruleset: 2+ positional args exits 1" {
  export MOCK_GH_AUTH_STATE=ok
  run _jailrun_ruleset owner/repo extra
  [ "$status" -eq 1 ]
  [[ "$output" == *"unexpected argument 'extra'"* ]]
}

# ========================================================================
# 4. リポジトリ自動検出
# ========================================================================

@test "RSR1 ruleset: git@ SSH URL detection (no args)" {
  export MOCK_GH_AUTH_STATE=ok
  export MOCK_GH_LIST_STATE=ok
  export MOCK_GH_RULESETS_NAMES=""
  export MOCK_GH_POST_STATE=ok
  export MOCK_GIT_REMOTE_STATE=ok
  export MOCK_GIT_REMOTE_URL="git@github.com:myorg/myrepo.git"
  run _jailrun_ruleset
  [ "$status" -eq 0 ]
  assert_gh_api_called POST "repos/myorg/myrepo/rulesets"
}

@test "RSR2 ruleset: https URL detection" {
  export MOCK_GH_AUTH_STATE=ok
  export MOCK_GH_LIST_STATE=ok
  export MOCK_GH_RULESETS_NAMES=""
  export MOCK_GH_POST_STATE=ok
  export MOCK_GIT_REMOTE_STATE=ok
  export MOCK_GIT_REMOTE_URL="https://github.com/myorg/myrepo.git"
  run _jailrun_ruleset
  [ "$status" -eq 0 ]
  assert_gh_api_called POST "repos/myorg/myrepo/rulesets"
}

@test "RSR3 ruleset: ssh:// URL detection" {
  export MOCK_GH_AUTH_STATE=ok
  export MOCK_GH_LIST_STATE=ok
  export MOCK_GH_RULESETS_NAMES=""
  export MOCK_GH_POST_STATE=ok
  export MOCK_GIT_REMOTE_STATE=ok
  export MOCK_GIT_REMOTE_URL="ssh://git@github.com/myorg/myrepo.git"
  run _jailrun_ruleset
  [ "$status" -eq 0 ]
  assert_gh_api_called POST "repos/myorg/myrepo/rulesets"
}

@test "RSR4 ruleset: https URL with user@ detection" {
  export MOCK_GH_AUTH_STATE=ok
  export MOCK_GH_LIST_STATE=ok
  export MOCK_GH_RULESETS_NAMES=""
  export MOCK_GH_POST_STATE=ok
  export MOCK_GIT_REMOTE_STATE=ok
  export MOCK_GIT_REMOTE_URL="https://user@github.com/myorg/myrepo.git"
  run _jailrun_ruleset
  [ "$status" -eq 0 ]
  assert_gh_api_called POST "repos/myorg/myrepo/rulesets"
}

@test "RSR5 ruleset: no remote (empty) exits 1" {
  export MOCK_GH_AUTH_STATE=ok
  export MOCK_GIT_REMOTE_STATE=empty
  run _jailrun_ruleset
  [ "$status" -eq 1 ]
  [[ "$output" == *"no git remote 'origin' found"* ]]
}

@test "RSR6 ruleset: unsupported URL format exits 1" {
  export MOCK_GH_AUTH_STATE=ok
  export MOCK_GIT_REMOTE_STATE=ok
  export MOCK_GIT_REMOTE_URL="gitlab.com:myorg/myrepo.git"
  run _jailrun_ruleset
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported remote URL format"* ]]
}
