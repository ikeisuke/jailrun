#!/bin/sh
# WSL2 host detection helper (no side effects).
# Sourced by lib/sandbox.sh (Section 2 platform dispatch direct prefix) and
# lib/platform/sandbox-linux-systemd.sh (idempotent / standalone-source).
#
# Provides: _is_wsl2()
# Requires: nothing (no globals, no external state)
#
# Intent SoT: lowercase uname -r matches microsoft|wsl2.
# Empty / failed uname -> return 1 (treat as native). LC_ALL=C pins tr locale
# (ASCII-only patterns). Variables scoped via `local` to avoid global leak.
# Issue #90 (Unit 001) / extracted from sandbox-linux-systemd.sh in v0.6.0 Unit 004
# for cross-platform availability (macOS dispatch path keeps function defined
# so WSL2 guards in lib/sandbox.sh no-op cleanly without stderr pollution).
_is_wsl2() {
  local _wsl_release _wsl_release_lc
  _wsl_release=$(uname -r 2>/dev/null) || return 1
  [ -n "$_wsl_release" ] || return 1
  _wsl_release_lc=$(printf '%s' "$_wsl_release" | LC_ALL=C tr '[:upper:]' '[:lower:]')
  case "$_wsl_release_lc" in
    *microsoft*|*wsl2*) return 0 ;;
    *)                  return 1 ;;
  esac
}
