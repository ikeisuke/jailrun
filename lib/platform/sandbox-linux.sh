#!/bin/sh
# Linux systemd-run sandbox 構築
# credential-guard.sh から source される
#
# 前提: $_tmpdir, $_WRAPPER_NAME, $_SANDBOX_DENY_READ_PATHS,
#        $_SANDBOX_ALLOW_WRITE_PATHS が設定済みであること（改行区切り）
# 出力: _setup_sandbox() 関数
#   _sandbox_cmd="systemd-run" （マーカー）
#   $_tmpdir/systemd-props にプロパティを書き出す

. "$JAILRUN_LIB/platform/git-worktree.sh"

_setup_sandbox() {
  local _cwd="$PWD"
  _detect_git_worktree

  if ! command -v systemd-run >/dev/null 2>&1; then
    echo "[$_WRAPPER_NAME] WARN: systemd-run が利用できません、サンドボックスなしで起動" >&2
    return
  fi

  _sandbox_cmd="systemd-run"
  local _props="$_tmpdir/systemd-props"
  {
    # 権限昇格防止
    echo '-p NoNewPrivileges=yes'
    echo '-p CapabilityBoundingSet='
    echo '-p AmbientCapabilities='
    echo '-p RestrictSUIDSGID=yes'
    echo '-p LockPersonality=yes'
    # デバイス制限
    echo '-p PrivateDevices=no'
    echo '-p DevicePolicy=closed'
    echo '-p DeviceAllow=/dev/null rw'
    echo '-p DeviceAllow=/dev/random r'
    echo '-p DeviceAllow=/dev/urandom r'
    # プロセス・IPC 分離
    echo '-p PrivateUsers=yes'
    echo '-p PrivateMounts=yes'
    echo '-p PrivateIPC=yes'
    echo '-p PrivateTmp=no'
    echo '-p ReadWritePaths=/tmp'
    # ネットワーク
    echo '-p PrivateNetwork=no'
    echo '-p RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6'
    # ファイルシステム
    echo '-p ProtectSystem=strict'
    echo '-p ProtectHome=read-only'
    printf '-p ReadWritePaths=%s\n' "$_cwd"
    printf '-p ReadWritePaths=%s\n' "$_tmpdir"
    # カーネル保護
    echo '-p ProtectProc=invisible'
    echo '-p ProtectClock=yes'
    echo '-p ProtectHostname=yes'
    echo '-p ProtectKernelLogs=yes'
    echo '-p ProtectKernelModules=yes'
    echo '-p ProtectKernelTunables=yes'
    echo '-p ProtectControlGroups=yes'
    # syscall フィルタ
    echo '-p SystemCallArchitectures=native'
    echo '-p SystemCallFilter=@system-service'
    echo '-p SystemCallFilter=~@privileged @debug'
    echo '-p SystemCallErrorNumber=EPERM'
    # namespace・リアルタイム制限
    echo '-p RestrictNamespaces=yes'
    echo '-p RestrictRealtime=yes'
    # その他
    echo '-p UMask=0077'
    echo '-p CoredumpFilter=0'
    echo '-p KeyringMode=private'
    # config ディレクトリの書き込み保護（明示）
    printf '-p ReadOnlyPaths=%s\n' "${CONFIG_DIR:-$HOME/.config/jailrun}"

    # git worktree
    if [ -n "$_git_parent_toplevel" ]; then
      printf '-p ReadWritePaths=%s\n' "$_git_parent_toplevel"
      if [ -n "$_other_worktrees" ]; then
        _OLD_IFS="$IFS"; IFS="
"
        for _wt in $_other_worktrees; do
          [ -d "$_wt" ] && printf '-p InaccessiblePaths=%s\n' "$_wt"
        done
        IFS="$_OLD_IFS"
      fi
    elif [ -n "$_git_common_dir" ]; then
      printf '-p ReadWritePaths=%s\n' "$_git_common_dir"
    fi

    # ホワイトリストのディレクトリを書き込み可能に
    _OLD_IFS="$IFS"; IFS="
"
    for _p in $_SANDBOX_ALLOW_WRITE_PATHS; do
      mkdir -p "$_p" 2>/dev/null || true
      printf '-p ReadWritePaths=%s\n' "$_p"
    done

    # 機密ディレクトリをアクセス不可に
    for _p in $_SANDBOX_DENY_READ_PATHS; do
      [ -d "$_p" ] && printf '-p InaccessiblePaths=%s\n' "$_p"
    done
    IFS="$_OLD_IFS"
  } > "$_props"
}
