#!/bin/sh
# Git worktree detection (shared by sandbox-darwin.sh / sandbox-linux.sh)
# After sourcing, the following variables are set:
#   _git_common_dir       - git common dir (empty if not a worktree)
#   _git_parent_toplevel  - parent repository toplevel (empty if not a worktree)
#   _other_worktrees      - paths of other worktrees (newline-separated)

_detect_git_worktree() {
  local _cwd="$PWD"
  _git_common_dir=""
  _git_parent_toplevel=""
  _other_worktrees=""

  command -v git >/dev/null 2>&1 || return 0

  _git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || true
  if [ -n "$_git_common_dir" ] && case "$_git_common_dir" in /*) false ;; *) true ;; esac; then
    _git_common_dir="$_cwd/$_git_common_dir"
  fi

  # Regular repository (under $_cwd) - no additional paths needed
  case "$_git_common_dir" in
    "$_cwd"/*)
      _git_common_dir=""
      return 0
      ;;
  esac

  [ -z "$_git_common_dir" ] && return 0

  # Worktree: get the parent repository toplevel
  _git_parent_toplevel="${_git_common_dir%/.git}"

  # Enumerate other worktrees (exclude self and parent)
  local _wt_path=""
  local _wt_tmp="$_tmpdir/worktrees"
  { git worktree list --porcelain 2>/dev/null; echo; } > "$_wt_tmp"
  while IFS= read -r _line; do
    case "$_line" in
      worktree\ *) _wt_path="${_line#worktree }" ;;
      "")
        if [ -n "$_wt_path" ] && [ "$_wt_path" != "$_cwd" ] && [ "$_wt_path" != "$_git_parent_toplevel" ]; then
          _other_worktrees="${_other_worktrees:+$_other_worktrees
}$_wt_path"
        fi
        _wt_path=""
        ;;
    esac
  done < "$_wt_tmp"
  return 0
}
