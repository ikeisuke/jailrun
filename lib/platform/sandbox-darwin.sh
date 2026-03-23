#!/bin/sh
# macOS Seatbelt sandbox 構築
# credential-guard.sh から source される
#
# 前提: $_tmpdir, $_SANDBOX_DENY_READ_PATHS, $_SANDBOX_ALLOW_WRITE_PATHS,
#        $_SANDBOX_ALLOW_WRITE_FILES が設定済みであること（改行区切り）
# 出力: _setup_sandbox() 関数（_sandbox_cmd を設定する）

. "$JAILRUN_LIB/platform/git-worktree.sh"

_setup_sandbox() {
  local _cwd="$PWD"
  _detect_git_worktree

  # Seatbelt プロファイル生成
  local _sb="$_tmpdir/sandbox.sb"
  {
    echo '(version 1)'
    echo '(allow default)'
    echo ''
    echo ';; 機密ディレクトリの読み取りを拒否'
    echo '(deny file-read*'
    _OLD_IFS="$IFS"; IFS="
"
    for _p in $_SANDBOX_DENY_READ_PATHS; do
      echo "  (subpath \"$_p\")"
    done
    IFS="$_OLD_IFS"
    echo ')'
    echo ''
    if [ "${AGENT_SANDBOX_DEBUG:-}" != "1" ]; then
      echo ';; 書き込みをホワイトリストに制限'
      echo '(deny file-write*'
      echo '  (require-not'
      echo '    (require-any'
      echo "      (subpath \"$_cwd\")"
      [ -n "$_git_parent_toplevel" ] && echo "      (subpath \"$_git_parent_toplevel\")"
      [ -z "$_git_parent_toplevel" ] && [ -n "$_git_common_dir" ] && echo "      (subpath \"$_git_common_dir\")"
      echo '      (subpath "/tmp")'
      echo '      (subpath "/private/tmp")'
      echo '      (subpath "/private/var/folders")'
      echo '      (literal "/dev/null")'
      echo '      (literal "/dev/zero")'
      echo '      (literal "/dev/random")'
      echo '      (literal "/dev/urandom")'
      echo "      (subpath \"$_tmpdir\")"
      _OLD_IFS="$IFS"; IFS="
"
      for _p in $_SANDBOX_ALLOW_WRITE_PATHS; do
        echo "      (subpath \"$_p\")"
      done
      for _f in $_SANDBOX_ALLOW_WRITE_FILES; do
        echo "      (literal \"$_f\")"
      done
      IFS="$_OLD_IFS"
      echo ')))'
      if [ -n "$_other_worktrees" ]; then
        echo ''
        echo ';; 他のワークツリーへの書き込みを拒否'
        echo '(deny file-write*'
        _OLD_IFS="$IFS"; IFS="
"
        for _wt in $_other_worktrees; do
          echo "  (subpath \"$_wt\")"
        done
        IFS="$_OLD_IFS"
        echo ')'
      fi
    else
      echo ';; デバッグ: 書き込み制限を無効化（読み取り拒否のみ有効）'
    fi
  } > "$_sb"
  _sandbox_cmd="sandbox-exec -f $_sb"
}
