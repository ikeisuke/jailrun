#!/usr/bin/env bats

@test "all scripts pass sh -n syntax check" {
  for f in bin/jailrun bin/bump-version lib/*.sh lib/platform/*.sh lib/shims/codex; do
    # lib/subcmd-registry.sh is intentionally bash-only (uses bash arrays as SoT
    # for agent subcmds, sourced by bin/jailrun which is bash). It is not meant
    # to be parsed by /bin/sh, so skip the sh -n gate for this file only.
    if [ "$(basename "$f")" = "subcmd-registry.sh" ]; then
      continue
    fi
    run sh -n "$f"
    if [ "$status" -ne 0 ]; then
      echo "FAIL: $f" >&2
      echo "$output" >&2
      return 1
    fi
  done
}

@test "no scripts have #!/bin/zsh shebang" {
  for f in bin/jailrun bin/bump-version lib/*.sh lib/platform/*.sh lib/shims/codex; do
    run head -1 "$f"
    [[ "$output" != *"/bin/zsh"* ]]
  done
}

@test "no scripts use zsh-only [[ ]] syntax" {
  # Grep for [[ that isn't in a comment or string
  for f in bin/jailrun bin/bump-version lib/*.sh lib/platform/*.sh lib/shims/codex; do
    run grep -n '^\s*\[\[' "$f"
    [ "$status" -ne 0 ]  # grep should find nothing
  done
}

@test "no scripts contain Japanese characters" {
  for f in bin/jailrun bin/bump-version lib/*.sh lib/platform/*.sh lib/shims/codex; do
    count=$(grep -cP '[\x{3040}-\x{309F}\x{30A0}-\x{30FF}\x{4E00}-\x{9FFF}]' "$f" 2>/dev/null || echo 0)
    if [ "$count" -gt 0 ]; then
      echo "FAIL: $f contains $count lines with Japanese" >&2
      return 1
    fi
  done
}
