#!/bin/sh
# Ruleset management - GitHub repository rulesets via gh API
# Usage: jailrun ruleset [options] [<owner/repo>]
#
# Creates branch protection and tag protection rulesets for a repository.

set -eu

_BRANCH_RULESET_NAME="jailrun-branch-protection"
_TAG_RULESET_NAME="jailrun-tag-protection"

# --- Helper functions ---

# Detect owner/repo from git remote origin
_detect_repo() {
  _remote_url=""
  _remote_url=$(git remote get-url origin 2>/dev/null) || true
  if [ -z "$_remote_url" ]; then
    echo "[ruleset] ERROR: no git remote 'origin' found" >&2
    echo "[ruleset] specify <owner/repo> explicitly" >&2
    return 1
  fi
  # Handle SSH: git@github.com:owner/repo.git
  # Handle HTTPS: https://github.com/owner/repo.git
  _repo=""
  case "$_remote_url" in
    git@github.com:*)
      _repo="${_remote_url#git@github.com:}"
      ;;
    https://github.com/*)
      _repo="${_remote_url#https://github.com/}"
      ;;
    ssh://git@github.com/*)
      _repo="${_remote_url#ssh://git@github.com/}"
      ;;
    *)
      echo "[ruleset] ERROR: unsupported remote URL format: $_remote_url" >&2
      return 1
      ;;
  esac
  # Strip .git suffix
  _repo="${_repo%.git}"
  echo "$_repo"
}

# Check that gh CLI is authenticated with sufficient permissions
_check_gh_auth() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "[ruleset] ERROR: gh CLI is not installed" >&2
    echo "[ruleset] install from https://cli.github.com/" >&2
    return 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "[ruleset] ERROR: gh CLI is not authenticated" >&2
    echo "[ruleset] run 'gh auth login' first" >&2
    return 1
  fi
}

# Check if a ruleset with a given name already exists
# Returns 0 if exists, 1 if not
_ruleset_exists() {
  _owner_repo="$1"
  _name="$2"
  _names=""
  _names=$(gh api "repos/${_owner_repo}/rulesets" --paginate --jq '.[].name' 2>/dev/null) || true
  if [ -z "$_names" ]; then
    return 1
  fi
  echo "$_names" | grep -qx "${_name}" && return 0
  return 1
}

# --- Ruleset creation ---

_create_branch_protection() {
  _owner_repo="$1"
  _dry_run="$2"

  echo "[ruleset] branch protection: $_BRANCH_RULESET_NAME"

  if _ruleset_exists "$_owner_repo" "$_BRANCH_RULESET_NAME"; then
    echo "[ruleset]   already exists, skipping"
    return 0
  fi

  _payload='{
  "name": "jailrun-branch-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "non_fast_forward"
    }
  ],
  "bypass_actors": []
}'

  if [ "$_dry_run" = "true" ]; then
    echo "[ruleset]   (dry-run) would create with:"
    echo "$_payload"
    return 0
  fi

  echo "$_payload" | gh api --method POST "repos/${_owner_repo}/rulesets" --input - >/dev/null
  echo "[ruleset]   created"
}

_create_tag_protection() {
  _owner_repo="$1"
  _dry_run="$2"

  echo "[ruleset] tag protection: $_TAG_RULESET_NAME"

  if _ruleset_exists "$_owner_repo" "$_TAG_RULESET_NAME"; then
    echo "[ruleset]   already exists, skipping"
    return 0
  fi

  _payload='{
  "name": "jailrun-tag-protection",
  "target": "tag",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~ALL"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "deletion"
    }
  ],
  "bypass_actors": []
}'

  if [ "$_dry_run" = "true" ]; then
    echo "[ruleset]   (dry-run) would create with:"
    echo "$_payload"
    return 0
  fi

  echo "$_payload" | gh api --method POST "repos/${_owner_repo}/rulesets" --input - >/dev/null
  echo "[ruleset]   created"
}

# --- Main entry point ---

_cmd_ruleset() {
  _dry_run="false"
  _repo_arg=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) _dry_run="true"; shift ;;
      --help|-h)
        cat <<'USAGE'
Usage: jailrun ruleset [options] [<owner/repo>]

Create GitHub repository rulesets for branch and tag protection.

Options:
  --dry-run    Show what would be configured without applying
  --help       Show this help

Arguments:
  <owner/repo>  Target repository (default: auto-detect from git remote)

Rulesets created:
  jailrun-branch-protection   Require PR + approval, block force-push (default branch)
  jailrun-tag-protection      Prevent tag deletion (all tags)

Prerequisites:
  - gh CLI installed and authenticated
  - Admin access to the target repository
USAGE
        return 0
        ;;
      -*)
        echo "[ruleset] ERROR: unknown option '$1'" >&2
        echo "Run 'jailrun ruleset --help' for usage" >&2
        return 1
        ;;
      *)
        if [ -n "$_repo_arg" ]; then
          echo "[ruleset] ERROR: unexpected argument '$1'" >&2
          echo "Run 'jailrun ruleset --help' for usage" >&2
          return 1
        fi
        _repo_arg="$1"; shift
        ;;
    esac
  done

  _check_gh_auth || return 1

  if [ -n "$_repo_arg" ]; then
    _owner_repo="$_repo_arg"
  else
    _owner_repo=$(_detect_repo) || return 1
  fi

  echo "[ruleset] target: $_owner_repo"
  if [ "$_dry_run" = "true" ]; then
    echo "[ruleset] mode: dry-run"
  fi
  echo ""

  _create_branch_protection "$_owner_repo" "$_dry_run"
  echo ""
  _create_tag_protection "$_owner_repo" "$_dry_run"

  echo ""
  echo "[ruleset] done"
}

# --- Dispatch ---

_cmd_ruleset "$@"
