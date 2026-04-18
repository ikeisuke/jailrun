#!/bin/sh
# Linux AppArmor filesystem sandbox backend
# Sourced by sandbox-linux.sh when AppArmor is available
#
# Requires: $_tmpdir, $_WRAPPER_NAME,
#           $_SANDBOX_DENY_READ_PATHS, $_SANDBOX_DENY_READ_REGEXES,
#           $_SANDBOX_ALLOW_WRITE_PATHS, $_SANDBOX_ALLOW_WRITE_LOCK_PATHS,
#           $_SANDBOX_ALLOW_WRITE_FILES,
#           $_git_parent_toplevel, $_git_common_dir, $_other_worktrees
# Provides: _build_apparmor_profile(), _load_apparmor_profile(),
#           _cleanup_sandbox()

# Escape a path for AppArmor double-quoted string context.
# Handles backslash and double-quote characters.
_apparmor_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Build AppArmor profile file at $_tmpdir/apparmor-profile.
# Sets $_apparmor_profile_name.
_build_apparmor_profile() {
  local _cwd="$PWD"
  local _profile="$_tmpdir/apparmor-profile"

  # Generate unique profile name
  _aa_rand=$(od -An -tx2 -N2 /dev/urandom | tr -d ' ')
  _apparmor_profile_name="jailrun_$(id -u)_$$_${_aa_rand}"

  {
    echo '#include <tunables/global>'
    echo ''
    printf 'profile %s flags=(attach_disconnected) {\n' "$_apparmor_profile_name"
    echo '  #include <abstractions/base>'
    echo ''
    echo '  # Default: allow read and execute everywhere'
    echo '  / r,'
    echo '  /** r,'
    echo '  /** ix,'

    _OLD_IFS="$IFS"; IFS="
"
    echo ''
    echo '  # Deny read: sensitive directories'
    for _p in $_SANDBOX_DENY_READ_PATHS; do
      echo "  deny \"$(_apparmor_escape "$_p")\"/ r,"
      echo "  deny \"$(_apparmor_escape "$_p")\"/** r,"
    done

    # Deny read: filename patterns (converted from regex to AppArmor glob)
    if [ -n "$_SANDBOX_DENY_READ_REGEXES" ]; then
      echo ''
      echo '  # Deny read: filename patterns'
      for _re in $_SANDBOX_DENY_READ_REGEXES; do
        # Input format: /<regex_escaped_name>$ (e.g. /\.env$)
        # Strip leading /, strip trailing $, remove regex escapes
        _name="${_re#/}"
        _name="${_name%?}"
        _name=$(printf '%s' "$_name" | sed 's/\\//g')
        echo "  deny /**/${_name} r,"
      done
    fi

    echo ''
    echo '  # Write whitelist'
    echo "  \"$(_apparmor_escape "$_cwd")\"/ rw,"
    echo "  \"$(_apparmor_escape "$_cwd")\"/** rwk,"
    echo '  /tmp/ rw,'
    echo '  /tmp/** rw,'
    echo "  \"$(_apparmor_escape "$_tmpdir")\"/ rw,"
    echo "  \"$(_apparmor_escape "$_tmpdir")\"/** rw,"

    if [ -n "$_git_parent_toplevel" ]; then
      echo "  \"$(_apparmor_escape "$_git_parent_toplevel")\"/ rw,"
      echo "  \"$(_apparmor_escape "$_git_parent_toplevel")\"/** rwk,"
    elif [ -n "$_git_common_dir" ]; then
      echo "  \"$(_apparmor_escape "$_git_common_dir")\"/ rw,"
      echo "  \"$(_apparmor_escape "$_git_common_dir")\"/** rwk,"
    fi

    for _p in $_SANDBOX_ALLOW_WRITE_PATHS; do
      echo "  \"$(_apparmor_escape "$_p")\"/ rw,"
      echo "  \"$(_apparmor_escape "$_p")\"/** rw,"
    done

    for _p in $_SANDBOX_ALLOW_WRITE_LOCK_PATHS; do
      echo "  \"$(_apparmor_escape "$_p")\"/ rwk,"
      echo "  \"$(_apparmor_escape "$_p")\"/** rwk,"
    done

    for _f in $_SANDBOX_ALLOW_WRITE_FILES; do
      echo "  \"$(_apparmor_escape "$_f")\" rw,"
      # Allow atomic write temp files (proper-lockfile pattern)
      echo "  \"$(_apparmor_escape "$_f")\".tmp.* rw,"
    done

    if [ -n "$_other_worktrees" ]; then
      echo ''
      echo '  # Deny writes to other worktrees'
      for _wt in $_other_worktrees; do
        echo "  deny \"$(_apparmor_escape "$_wt")\"/ w,"
        echo "  deny \"$(_apparmor_escape "$_wt")\"/** w,"
      done
    fi

    echo ''
    echo '  # Config directory: read-only'
    _config_path="${CONFIG_DIR:-$HOME/.config/jailrun}"
    echo "  deny \"$(_apparmor_escape "$_config_path")\"/ w,"
    echo "  deny \"$(_apparmor_escape "$_config_path")\"/** w,"

    echo ''
    echo '  # D-Bus session bus socket'
    echo '  deny /run/user/*/bus rw,'

    IFS="$_OLD_IFS"
    echo '}'
  } > "$_profile"
}

# Load AppArmor profile into kernel. Returns 0 on success.
_load_apparmor_profile() {
  if sudo -n apparmor_parser -r "$_tmpdir/apparmor-profile" 2>/dev/null; then
    _APPARMOR_PROFILE_LOADED=1
    return 0
  fi
  echo "[$_WRAPPER_NAME] WARN: failed to load AppArmor profile (sudo required), falling back to systemd" >&2
  _APPARMOR_PROFILE_LOADED=""
  return 1
}

# Unload AppArmor profile from kernel (called by sandbox.sh EXIT trap)
_cleanup_sandbox() {
  if [ -n "${_APPARMOR_PROFILE_LOADED:-}" ] && [ -f "$_tmpdir/apparmor-profile" ]; then
    sudo -n apparmor_parser -R "$_tmpdir/apparmor-profile" 2>/dev/null || true
  fi
}
