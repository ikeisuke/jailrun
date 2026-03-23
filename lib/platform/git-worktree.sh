#!/bin/sh
# git worktree 検出（sandbox-darwin.sh / sandbox-linux.sh 共通）
# source 後に以下の変数が設定される:
#   _git_common_dir       - git common dir（worktree 以外では空）
#   _git_parent_toplevel  - 親リポジトリの toplevel（worktree 以外では空）
#   _other_worktrees      - 他のワークツリーのパス（改行区切り）

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

  # 通常リポジトリ（$_cwd 配下）なら追加不要
  case "$_git_common_dir" in
    "$_cwd"/*)
      _git_common_dir=""
      return 0
      ;;
  esac

  [ -z "$_git_common_dir" ] && return 0

  # worktree: 親リポジトリの toplevel を取得
  _git_parent_toplevel="${_git_common_dir%/.git}"

  # 他のワークツリーを列挙（自分自身と親は除外）
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
