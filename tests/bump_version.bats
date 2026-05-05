#!/usr/bin/env bats

# Tests for bin/bump-version
#
# All tests run inside an isolated fixture git repository under BATS_TEST_TMPDIR,
# so the real repository's .git, working tree, and tags are never touched.

setup() {
  BUMP_VERSION="$BATS_TEST_DIRNAME/../bin/bump-version"
  FIXTURE_REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FIXTURE_REPO/bin"
  cat > "$FIXTURE_REPO/bin/jailrun" <<'EOF'
#!/bin/sh
set -eu

VERSION="0.1.0"

echo "jailrun $VERSION"
EOF
  chmod +x "$FIXTURE_REPO/bin/jailrun"
  printf '# Change History\n\n## v0.0.1 \342\200\224 seed (2020-01-01)\n\nSeed entry.\n' > "$FIXTURE_REPO/HISTORY.md"
  cd "$FIXTURE_REPO"
  git init --quiet
  git config user.email "test@example.com"
  git config user.name "Test"
  git add bin/jailrun HISTORY.md
  git commit --quiet -m "seed"
}

# Snapshot file contents and git tag list. Use inside a test to verify "no state change".
snapshot_state() {
  VERSION_BEFORE=$(cat bin/jailrun)
  HISTORY_BEFORE=$(cat HISTORY.md)
  TAGS_BEFORE=$(git tag --list)
  STATUS_BEFORE=$(git status --porcelain)
}

assert_no_state_change() {
  [ "$(cat bin/jailrun)" = "$VERSION_BEFORE" ] || { echo "bin/jailrun changed" >&2; return 1; }
  [ "$(cat HISTORY.md)" = "$HISTORY_BEFORE" ] || { echo "HISTORY.md changed" >&2; return 1; }
  [ "$(git tag --list)" = "$TAGS_BEFORE" ] || { echo "git tag list changed" >&2; return 1; }
  [ "$(git status --porcelain)" = "$STATUS_BEFORE" ] || { echo "git status changed" >&2; return 1; }
}

@test "dry-run outputs diff and does not modify files" {
  snapshot_state
  run "$BUMP_VERSION" 0.2.0 --message "Release 0.2.0" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"(dry-run) VERSION: 0.1.0 -> 0.2.0"* ]]
  [[ "$output" == *"(dry-run) HISTORY.md"* ]]
  assert_no_state_change
}

@test "dry-run --tag succeeds outside a git repository (no git operations)" {
  # Move the fixture contents to a non-git directory so any git call would fail.
  NONGIT="$BATS_TEST_TMPDIR/nongit"
  mkdir -p "$NONGIT/bin"
  cp -p bin/jailrun "$NONGIT/bin/jailrun"
  cp -p HISTORY.md "$NONGIT/HISTORY.md"
  cd "$NONGIT"
  [ ! -d .git ]
  run "$BUMP_VERSION" 0.2.0 --message "Release 0.2.0" --tag --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"(would create)"* ]]
  # Nothing should have been written.
  grep -qE '^VERSION="0\.1\.0"$' bin/jailrun
}

@test "bin/jailrun retains executable permission after bump" {
  before_perm=$(ls -l bin/jailrun | awk '{print $1}')
  [[ "$before_perm" == *x* ]]
  run "$BUMP_VERSION" 0.2.0 --message "Release 0.2.0"
  [ "$status" -eq 0 ]
  after_perm=$(ls -l bin/jailrun | awk '{print $1}')
  [[ "$after_perm" == *x* ]]
  [ -x bin/jailrun ]
}

@test "normal run with MAJOR.MINOR.PATCH updates VERSION and HISTORY.md" {
  run "$BUMP_VERSION" 0.2.0 --message "Release 0.2.0"
  [ "$status" -eq 0 ]
  grep -qE '^VERSION="0\.2\.0"$' bin/jailrun
  # HISTORY.md second line should be blank, third line should be new entry
  head -n 3 HISTORY.md | tail -n 1 | grep -q "0.2.0"
  head -n 3 HISTORY.md | tail -n 1 | grep -q "Release 0.2.0"
}

@test "v-prefixed version is normalized identically to bare version" {
  run "$BUMP_VERSION" v0.2.0 --message "Release 0.2.0"
  [ "$status" -eq 0 ]
  grep -qE '^VERSION="0\.2\.0"$' bin/jailrun
  grep -qE '^## v0\.2\.0 ' HISTORY.md
}

@test "title can be provided via stdin when --message is omitted" {
  run sh -c "echo 'Release via stdin' | '$BUMP_VERSION' 0.2.0"
  [ "$status" -eq 0 ]
  grep -q "Release via stdin" HISTORY.md
}

@test "TG1 --tag fails outside a git repository with controlled die message" {
  # NOTE: Cycle v0.3.2 / Unit 002 / Issue #50
  # 事前ガード (git rev-parse --git-dir) が _ARG_TAG=1 && _ARG_DRY_RUN=0 経路で発火し、
  # 制御された die() メッセージで終了することを検証する。
  NONGIT="$BATS_TEST_TMPDIR/nongit"
  mkdir -p "$NONGIT/bin"
  cp -p bin/jailrun "$NONGIT/bin/jailrun"
  cp -p HISTORY.md "$NONGIT/HISTORY.md"
  cd "$NONGIT"
  [ ! -d .git ]
  run "$BUMP_VERSION" 0.2.0 --message "Release 0.2.0" --tag
  [ "$status" -eq 1 ]
  # die() 経路通過の証拠: [bump-version] プレフィックスを含む
  [[ "$output" == *"[bump-version]"* ]]
  # 制御メッセージ本文を含む
  [[ "$output" == *"--tag requires a git repository"* ]]
  # 生 git エラーが露出していない
  [[ "$output" != *"fatal: not a git repository"* ]]
  # ファイル変更なし (VERSION は fixture の 0.1.0 のまま)
  grep -qE '^VERSION="0\.1\.0"$' bin/jailrun
}

@test "--tag creates git tag v<version>" {
  run "$BUMP_VERSION" 0.2.0 --message "Release 0.2.0" --tag
  [ "$status" -eq 0 ]
  run git tag --list "v0.2.0"
  [[ "$output" == "v0.2.0" ]]
}

@test "--tag creates a commit and tag references the bumped contents" {
  before_head=$(git rev-parse HEAD)
  before_count=$(git rev-list --count HEAD)
  run "$BUMP_VERSION" 0.2.0 --message "Release 0.2.0" --tag
  [ "$status" -eq 0 ]
  after_head=$(git rev-parse HEAD)
  after_count=$(git rev-list --count HEAD)
  # A new commit must have been created so the tag references release contents (not pre-bump HEAD).
  [ "$before_head" != "$after_head" ]
  [ "$after_count" -eq $((before_count + 1)) ]
  # The tag must reference the new HEAD, and the new HEAD must contain the bumped VERSION.
  tag_ref=$(git rev-list -n1 v0.2.0)
  [ "$tag_ref" = "$after_head" ]
  git show "HEAD:bin/jailrun" | grep -qE '^VERSION="0\.2\.0"$'
  git show "HEAD:HISTORY.md" | grep -q "## v0.2.0"
}

@test "without --tag no git tag is created" {
  run "$BUMP_VERSION" 0.2.0 --message "Release 0.2.0"
  [ "$status" -eq 0 ]
  run git tag --list
  [[ "$output" != *"v0.2.0"* ]]
}

@test "invalid version format exits 1 with no state change" {
  for bad in abc 1.2 v1.2.3.4; do
    snapshot_state
    run "$BUMP_VERSION" "$bad" --message "oops"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid version format"* ]]
    assert_no_state_change
  done
}

@test "duplicate version (equals current) exits 1 with no state change" {
  snapshot_state
  run "$BUMP_VERSION" 0.1.0 --message "same"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing to bump"* ]]
  assert_no_state_change
}

@test "existing git tag causes failure and no file change" {
  git tag v0.2.0
  snapshot_state
  run "$BUMP_VERSION" 0.2.0 --message "Release 0.2.0" --tag
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
  assert_no_state_change
}

@test "malformed HISTORY.md exits 1 with no state change" {
  printf 'not a change log\n\n## v0.0.1 seed\n' > HISTORY.md
  git add HISTORY.md
  git commit --quiet -m "break history"
  snapshot_state
  run "$BUMP_VERSION" 0.2.0 --message "Release 0.2.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Change History"* ]]
  assert_no_state_change
}

@test "HISTORY.md first heading with incomplete format exits 1 with no state change" {
  # Heading has the vX.Y.Z prefix but no em-dash title or date trailer.
  printf '# Change History\n\n## v0.0.1\n' > HISTORY.md
  git add HISTORY.md
  git commit --quiet -m "incomplete heading"
  snapshot_state
  run "$BUMP_VERSION" 0.2.0 --message "Release 0.2.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must match"* ]]
  assert_no_state_change
}

@test "HISTORY.md already contains the target version heading exits 1 with no state change" {
  # Prepend a canonical v0.2.0 heading so that bump of 0.2.0 should collide.
  printf '# Change History\n\n## v0.2.0 \342\200\224 already released (2026-01-01)\n\n## v0.0.1 \342\200\224 seed (2020-01-01)\n' > HISTORY.md
  # Bump current VERSION so version-equality check does not short-circuit first.
  sed -i.bak 's/VERSION="0.1.0"/VERSION="0.0.9"/' bin/jailrun
  rm -f bin/jailrun.bak
  git add bin/jailrun HISTORY.md
  git commit --quiet -m "seed with existing v0.2.0 entry"
  snapshot_state
  run "$BUMP_VERSION" 0.2.0 --message "Release 0.2.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already contains entry for v0.2.0"* ]]
  assert_no_state_change
}

@test "missing HISTORY.md exits 1 and bin/jailrun untouched" {
  rm HISTORY.md
  git add -A
  git commit --quiet -m "remove history"
  VERSION_BEFORE=$(cat bin/jailrun)
  TAGS_BEFORE=$(git tag --list)
  run "$BUMP_VERSION" 0.2.0 --message "Release 0.2.0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"HISTORY.md not found"* ]]
  [ "$(cat bin/jailrun)" = "$VERSION_BEFORE" ]
  [ "$(git tag --list)" = "$TAGS_BEFORE" ]
}

@test "missing message and empty stdin exits 1 with no state change" {
  snapshot_state
  run sh -c "'$BUMP_VERSION' 0.2.0 < /dev/null"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stdin is empty"* ]]
  assert_no_state_change
}

@test "multi-line --message is rejected" {
  snapshot_state
  run "$BUMP_VERSION" 0.2.0 --message "first line
second line"
  [ "$status" -eq 1 ]
  [[ "$output" == *"newline"* ]]
  assert_no_state_change
}

@test "dirty worktree blocks --tag with no state change" {
  echo "# noise" >> README_noise.md
  snapshot_state
  run "$BUMP_VERSION" 0.2.0 --message "Release 0.2.0" --tag
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes"* ]]
  assert_no_state_change
}
