# shellcheck shell=bash
# Agent subcmd single source of truth (SoT) for bin/jailrun.
#
# Constraints on JAILRUN_AGENT_SUBCOMMANDS entries:
#   - format: "name:description" (first ':' is the delimiter; ':' inside description is allowed)
#   - name must not be empty and must not contain ':'
#   - description must not be empty
#   - name must be unique within the array
#   - name must not collide with reserved commands:
#       exec-type subcmds : token / config / ruleset
#       control subcmds   : --help / -h / --version / -v
#
# Consumers:
#   - bin/jailrun : sources this file, calls _jailrun_validate_agent_subcommands
#                    as fail-fast guard, then uses _jailrun_is_agent_subcmd for
#                    dispatch derivation and _jailrun_print_agent_help_lines for
#                    --help Commands rendering.
#
# bash 3.2 compatibility note: macOS /bin/bash is 3.2, so this file MUST NOT use
# `declare -A` or other bash 4+ features.

JAILRUN_AGENT_SUBCOMMANDS=(
  "claude:launch Claude Code"
  "codex:launch Codex"
  "gemini:launch Gemini CLI"
  "kiro-cli:launch Kiro CLI"
  "kiro-cli-chat:launch Kiro CLI Chat"
  "copilot:launch GitHub Copilot CLI"
)

# Fail-fast validator for JAILRUN_AGENT_SUBCOMMANDS.
# Returns 0 if valid, 1 if any rule fails. Emits a single stderr message on
# the first violation found.
_jailrun_validate_agent_subcommands() {
  local _entry _name _desc _i _j _other_name
  local _len=${#JAILRUN_AGENT_SUBCOMMANDS[@]}

  # Rule A: per-entry format
  for _entry in "${JAILRUN_AGENT_SUBCOMMANDS[@]}"; do
    if [ -z "$_entry" ]; then
      echo "bin/jailrun: invalid JAILRUN_AGENT_SUBCOMMANDS entry: \"\" (expected \"name:description\" with non-empty name and description)" >&2
      return 1
    fi
    case "$_entry" in
      *:*) ;;
      *)
        echo "bin/jailrun: invalid JAILRUN_AGENT_SUBCOMMANDS entry: \"$_entry\" (expected \"name:description\" with non-empty name and description)" >&2
        return 1
        ;;
    esac
    _name="${_entry%%:*}"
    _desc="${_entry#*:}"
    if [ -z "$_name" ] || [ -z "$_desc" ]; then
      echo "bin/jailrun: invalid JAILRUN_AGENT_SUBCOMMANDS entry: \"$_entry\" (expected \"name:description\" with non-empty name and description)" >&2
      return 1
    fi
  done

  # Rule C: reserved-name collision
  for _entry in "${JAILRUN_AGENT_SUBCOMMANDS[@]}"; do
    _name="${_entry%%:*}"
    case "$_name" in
      token|config|ruleset|--help|-h|--version|-v)
        echo "bin/jailrun: subcmd name \"$_name\" in JAILRUN_AGENT_SUBCOMMANDS collides with reserved command" >&2
        return 1
        ;;
    esac
  done

  # Rule B: name uniqueness (bash 3.2 compatible: nested loop, no `declare -A`)
  _i=0
  while [ "$_i" -lt "$_len" ]; do
    _name="${JAILRUN_AGENT_SUBCOMMANDS[$_i]%%:*}"
    _j=$((_i + 1))
    while [ "$_j" -lt "$_len" ]; do
      _other_name="${JAILRUN_AGENT_SUBCOMMANDS[$_j]%%:*}"
      if [ "$_name" = "$_other_name" ]; then
        echo "bin/jailrun: duplicate subcmd name \"$_name\" in JAILRUN_AGENT_SUBCOMMANDS" >&2
        return 1
      fi
      _j=$((_j + 1))
    done
    _i=$((_i + 1))
  done

  return 0
}

# Returns 0 if $1 matches an agent subcmd name from the SoT, 1 otherwise.
_jailrun_is_agent_subcmd() {
  local _target="$1" _entry
  for _entry in "${JAILRUN_AGENT_SUBCOMMANDS[@]}"; do
    if [ "${_entry%%:*}" = "$_target" ]; then
      return 0
    fi
  done
  return 1
}

# Prints each agent subcmd as "  <name(20 cols left-padded)><description>".
# Used by bin/jailrun --help to derive the Commands: agent rows from the SoT.
_jailrun_print_agent_help_lines() {
  local _entry
  for _entry in "${JAILRUN_AGENT_SUBCOMMANDS[@]}"; do
    printf '  %-20s%s\n' "${_entry%%:*}" "${_entry#*:}"
  done
}
