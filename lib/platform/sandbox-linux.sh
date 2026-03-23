#!/bin/zsh
# Linux systemd-run sandbox 構築
# credential-guard.sh から source される
#
# 前提: $_tmpdir, $_WRAPPER_NAME, $_SANDBOX_DENY_READ_PATHS,
#        $_SANDBOX_ALLOW_WRITE_PATHS が設定済みであること
# 出力: _setup_sandbox() 関数（_sandbox_cmd 配列を設定する）

_setup_sandbox() {
  local _cwd="$PWD"
  local _git_common_dir="" _git_parent_toplevel=""
  local _other_worktrees=()

  # git worktree 検出
  if command -v git >/dev/null 2>&1; then
    _git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || true
    if [[ -n "$_git_common_dir" && "$_git_common_dir" != /* ]]; then
      _git_common_dir="$_cwd/$_git_common_dir"
    fi
    if [[ -n "$_git_common_dir" && "$_git_common_dir" == "$_cwd"/* ]]; then
      _git_common_dir=""
    elif [[ -n "$_git_common_dir" ]]; then
      _git_parent_toplevel="${_git_common_dir%/.git}"
      local _wt_path=""
      while IFS= read -r _line; do
        case "$_line" in
          worktree\ *) _wt_path="${_line#worktree }" ;;
          "")
            if [[ -n "$_wt_path" && "$_wt_path" != "$_cwd" && "$_wt_path" != "$_git_parent_toplevel" ]]; then
              _other_worktrees+=("$_wt_path")
            fi
            _wt_path=""
            ;;
        esac
      done < <(git worktree list --porcelain 2>/dev/null; echo)
    fi
  fi

  if ! command -v systemd-run >/dev/null 2>&1; then
    echo "[$_WRAPPER_NAME] WARN: systemd-run が利用できません、サンドボックスなしで起動" >&2
    return
  fi

  _sandbox_cmd=(
    systemd-run
    --user --pty --wait --collect --same-dir
    -E PATH="$PATH"
    # 権限昇格防止
    -p NoNewPrivileges=yes
    -p CapabilityBoundingSet=
    -p AmbientCapabilities=
    -p RestrictSUIDSGID=yes
    -p LockPersonality=yes
    # デバイス制限
    -p PrivateDevices=no
    -p DevicePolicy=closed
    -p "DeviceAllow=/dev/null rw"
    -p "DeviceAllow=/dev/random r"
    -p "DeviceAllow=/dev/urandom r"
    # プロセス・IPC 分離
    -p PrivateUsers=yes
    -p PrivateMounts=yes
    -p PrivateIPC=yes
    -p PrivateTmp=no
    -p "ReadWritePaths=/tmp"
    # ネットワーク
    -p PrivateNetwork=no
    -p "RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6"
    # ファイルシステム
    -p ProtectSystem=strict
    -p ProtectHome=read-only
    -p "ReadWritePaths=$_cwd"
    -p "ReadWritePaths=$_tmpdir"
    # カーネル保護
    -p ProtectProc=invisible
    -p ProtectClock=yes
    -p ProtectHostname=yes
    -p ProtectKernelLogs=yes
    -p ProtectKernelModules=yes
    -p ProtectKernelTunables=yes
    -p ProtectControlGroups=yes
    # syscall フィルタ
    -p SystemCallArchitectures=native
    -p "SystemCallFilter=@system-service"
    -p "SystemCallFilter=~@privileged @debug"
    -p SystemCallErrorNumber=EPERM
    # namespace・リアルタイム制限
    -p RestrictNamespaces=yes
    -p RestrictRealtime=yes
    # その他
    -p UMask=0077
    -p CoredumpFilter=0
    -p KeyringMode=private
  )

  # git worktree
  if [[ -n "$_git_parent_toplevel" ]]; then
    _sandbox_cmd+=(-p "ReadWritePaths=$_git_parent_toplevel")
    for _wt in "${_other_worktrees[@]}"; do
      [[ -d "$_wt" ]] && _sandbox_cmd+=(-p "InaccessiblePaths=$_wt")
    done
  elif [[ -n "$_git_common_dir" ]]; then
    _sandbox_cmd+=(-p "ReadWritePaths=$_git_common_dir")
  fi

  # ホワイトリストのディレクトリを書き込み可能に
  for _p in "${_SANDBOX_ALLOW_WRITE_PATHS[@]}"; do
    mkdir -p "$_p" 2>/dev/null || true
    _sandbox_cmd+=(-p "ReadWritePaths=$_p")
  done

  # 機密ディレクトリをアクセス不可に
  for _p in "${_SANDBOX_DENY_READ_PATHS[@]}"; do
    [[ -d "$_p" ]] && _sandbox_cmd+=(-p "InaccessiblePaths=$_p")
  done
}
