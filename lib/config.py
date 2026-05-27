#!/usr/bin/env python3
"""jailrun configuration API (TOML-based).

This module provides the core configuration loading, merging, and writing
functionality. For the CLI interface, see config_cli.py.
"""

from __future__ import annotations

import os
import re
import sys
import copy
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:
    # Python 3.10 and below: try tomli (pip install tomli)
    try:
        import tomli as tomllib
    except ImportError:
        print("ERROR: Python 3.11+ required (or install 'tomli' for 3.10)", file=sys.stderr)
        sys.exit(1)

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

DEFAULTS: dict = {
    "gh_token_name": "classic",
    "allowed_aws_profiles": ["default"],
    "default_aws_profile": "default",
    "default_region": "ap-northeast-1",
    "sandbox_deny_read_names": [],
    "sandbox_extra_deny_read": [],
    "sandbox_extra_allow_write": [],
    "sandbox_extra_allow_write_files": [],
    "sandbox_passthrough_env": [],
    "proxy_enabled": False,
    "proxy_allow_domains": [],
    "keychain_profile": "allow",
}

VALID_KEYCHAIN_PROFILES = {"deny", "read-cache-only", "allow"}

LIST_KEYS = {
    "allowed_aws_profiles",
    "sandbox_deny_read_names",
    "sandbox_extra_deny_read",
    "sandbox_extra_allow_write",
    "sandbox_extra_allow_write_files",
    "sandbox_passthrough_env",
    "proxy_allow_domains",
}

KNOWN_KEYS = set(DEFAULTS.keys())

# Built-in proxy allow domains per agent (merged when proxy is enabled)
BUILTIN_PROXY_DOMAINS: dict[str, list[str]] = {
    "claude": [
        # Core API endpoints (Anthropic).
        "api.anthropic.com",
        "statsig.anthropic.com",
        # Claude Code itself: workspace / plugins traffic and auto-update.
        "platform.claude.com",
        "downloads.claude.ai",
        # claude -> codex passthrough (claude session invoking codex CLI).
        "chatgpt.com",
        "ab.chatgpt.com",
        "api.openai.com",
        # Telemetry. Uncomment to allow.
        # "http-intake.logs.us5.datadoghq.com",
    ],
    "codex": [
        "chatgpt.com",
        "ab.chatgpt.com",
        "api.openai.com",
    ],
    "kiro-cli": [
        "*.kiro.dev",
        "q.us-east-1.amazonaws.com",
        "q.eu-central-1.amazonaws.com",
        "desktop-release.q.us-east-1.amazonaws.com",
        "cognito-identity.us-east-1.amazonaws.com",
        "oidc.ap-northeast-1.amazonaws.com",
        "*.awsapps.com",
        "client-telemetry.us-east-1.amazonaws.com",
    ],
    # gemini CLI: minimum reach categories per Issue #85 / Intent M3
    #   - auth: Google OAuth flow + account selection
    #   - api:  Gemini Code Assist (primary) / Gemini API (direct, API-key path)
    # The exact set is provisional; verify against actual gemini connections
    # (see README "WSL2 network restriction" section for the runtime check).
    "gemini": [
        # Auth: Google OAuth flow + account selection.
        "accounts.google.com",
        "oauth2.googleapis.com",
        # API: Gemini Code Assist is the primary path observed in practice.
        "cloudcode-pa.googleapis.com",
        # Direct Gemini API path (used when an API key is set instead of OAuth).
        "generativelanguage.googleapis.com",
        # Telemetry. Uncomment to allow.
        # "www.google-analytics.com",
    ],
}
# Common to every agent: GitHub-family + npm registry endpoints all CLIs need
# regardless of vendor. The rationale for keeping these in COMMON (not
# per-agent):
#   - github.com               : user-level OAuth flow, repository browsing
#   - api.github.com           : releases / PR / Issue REST API
#   - raw.githubusercontent.com: configuration files, release assets, raw
#                                content fetched by setup / install scripts
#   - registry.npmjs.org       : npm package fetch invoked by any agent that
#                                operates on a node project (observed for
#                                codex, applies equally to claude / gemini)
# When adding a new agent, only place a domain here if it is genuinely shared
# by every agent; otherwise put it in BUILTIN_PROXY_DOMAINS[<agent>].
BUILTIN_PROXY_DOMAINS_COMMON: list[str] = [
    "github.com",
    "api.github.com",
    "raw.githubusercontent.com",
    "registry.npmjs.org",
]

DEFAULT_TOML = """\
# jailrun config (TOML format)
# Docs: https://github.com/ikeisuke/jailrun

[global]
gh_token_name = "classic"
allowed_aws_profiles = ["default"]
default_aws_profile = "default"
# default_region = "ap-northeast-1"

# deny read by filename (matched anywhere in the filesystem, macOS only)
# sandbox_deny_read_names = [".env"]

# additional read-deny paths (default: ~/.aws ~/.ssh ~/.gnupg ~/.config/gh)
# sandbox_extra_deny_read = []

# additional write-allow paths (default: ~/.claude ~/.codex ~/.kiro etc.)
# sandbox_extra_allow_write = []

# additional write-allow files
# sandbox_extra_allow_write_files = []

# environment variables to pass through to sandbox
# sandbox_passthrough_env = ["ANTHROPIC_API_KEY"]

# --- Keychain access profile (macOS only) ---
# Controls ~/Library/Keychains write access in the Seatbelt sandbox.
#   "allow"           - full write access (default, needed for in-sandbox auth)
#   "deny"            - block all Keychain writes (authenticate outside sandbox first)
#   "read-cache-only" - same as deny (cached auth state is read via SecurityServer)
# keychain_profile = "allow"

# --- Network proxy (HTTPS CONNECT with domain allowlist) ---
# proxy_enabled = false
# proxy_allow_domains = ["api.anthropic.com", "api.openai.com", "github.com"]

# --- Profiles ---
# [profile.restricted]
# sandbox_passthrough_env = []

# [profile.ml-dev]
# sandbox_extra_allow_write = ["~/data", "~/models"]
# sandbox_passthrough_env = ["CUDA_VISIBLE_DEVICES"]

# --- Per-directory overrides ---
# [dir."/home/user/projects/ml"]
# profile = "ml-dev"
# sandbox_extra_allow_write = ["~/datasets"]

# --- Per-app default profiles ---
# [app.claude]
# profile = "restricted"
"""

# ---------------------------------------------------------------------------
# Config paths
# ---------------------------------------------------------------------------

def config_dir() -> Path:
    xdg = os.environ.get("XDG_CONFIG_HOME", os.path.join(Path.home(), ".config"))
    return Path(xdg) / "jailrun"


def config_file() -> Path:
    return config_dir() / "config.toml"


def legacy_config_file() -> Path:
    xdg = os.environ.get("XDG_CONFIG_HOME", os.path.join(Path.home(), ".config"))
    return Path(xdg) / "jailrun" / "config"


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def load_toml(path: Path) -> dict:
    with open(path, "rb") as f:
        return tomllib.load(f)


def merge_layer(base: dict, layer: dict, append_lists: bool = False) -> dict:
    """Merge layer into base. Lists append (if append_lists) or overwrite, scalars overwrite."""
    result = copy.deepcopy(base)
    for k, v in layer.items():
        if append_lists and k in LIST_KEYS and isinstance(v, list) and isinstance(result.get(k), list):
            # Append, deduplicate while preserving order
            seen = set(result[k])
            for item in v:
                if item not in seen:
                    result[k].append(item)
                    seen.add(item)
        else:
            result[k] = v
    return result


def resolve_config(app: str = "", directory: str = "") -> dict:
    """Load and merge config layers: defaults -> global -> profile -> app settings -> dir."""
    result = copy.deepcopy(DEFAULTS)

    path = config_file()
    if not path.exists():
        return result

    raw = load_toml(path)

    # Layer 1: [global] — overwrites defaults
    if "global" in raw:
        result = merge_layer(result, raw["global"])

    # Determine profile from app or dir
    profile_name = ""
    app_settings = {}

    # Layer 2: [app.<name>] -> extract profile name and settings
    if app and "app" in raw and app in raw["app"]:
        app_conf = raw["app"][app]
        if "profile" in app_conf:
            profile_name = app_conf["profile"]
        app_settings = {k: v for k, v in app_conf.items() if k != "profile"}

    # Layer 3: [dir."<path>"] -> may override profile
    # Supports ~ / $HOME expansion in keys (Issue #55).
    # Keys whose expansion still contains an unresolved $VAR / ${VAR} are
    # skipped to avoid false matches against undefined env vars. A literal
    # "$" in a path (without VAR-name characters) is allowed.
    dir_conf = {}
    if directory and "dir" in raw:
        best_match_expanded = ""
        best_match_key = ""
        for dir_key in raw["dir"]:
            expanded = os.path.expanduser(os.path.expandvars(dir_key))
            if _UNDEFINED_VAR_RE.search(expanded):
                continue
            if directory == expanded or directory.startswith(expanded.rstrip("/") + "/"):
                if len(expanded) > len(best_match_expanded):
                    best_match_expanded = expanded
                    best_match_key = dir_key
        if best_match_key:
            dir_conf = raw["dir"][best_match_key]
            if "profile" in dir_conf:
                profile_name = dir_conf["profile"]

    # Layer 4: Apply profile — appends to lists
    if profile_name and "profile" in raw and profile_name in raw["profile"]:
        result = merge_layer(result, raw["profile"][profile_name], append_lists=True)

    # Layer 5: Apply app settings (non-profile) — appends to lists
    # Applied AFTER profile so app-specific overrides take precedence
    if app_settings:
        result = merge_layer(result, app_settings, append_lists=True)

    # Layer 6: Apply dir settings (non-profile) — appends to lists
    if dir_conf:
        dir_settings = {k: v for k, v in dir_conf.items() if k != "profile"}
        if dir_settings:
            result = merge_layer(result, dir_settings, append_lists=True)

    # Validate enum fields
    kp = result.get("keychain_profile", "allow")
    if kp not in VALID_KEYCHAIN_PROFILES:
        raise ValueError(
            f'Invalid keychain_profile: "{kp}". '
            f"Must be one of: {', '.join(sorted(VALID_KEYCHAIN_PROFILES))}"
        )

    # Merge built-in proxy domains (common + per-agent)
    if result.get("proxy_enabled"):
        builtin = list(BUILTIN_PROXY_DOMAINS_COMMON)
        if app and app in BUILTIN_PROXY_DOMAINS:
            builtin.extend(BUILTIN_PROXY_DOMAINS[app])
        existing = set(result.get("proxy_allow_domains", []))
        for d in builtin:
            if d not in existing:
                result.setdefault("proxy_allow_domains", []).append(d)
                existing.add(d)

    return result


# ---------------------------------------------------------------------------
# Shell output
# ---------------------------------------------------------------------------

# Patterns used by the shell envelope (Issue #48 / #55).
_SHELL_KEY_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")
_UNDEFINED_VAR_RE = re.compile(r"\$(?:\{[A-Za-z_]\w*\}?|[A-Za-z_]\w*)")


def shell_escape(value: str) -> str:
    """Escape a string for safe embedding in double-quoted shell context.

    Retained for backward compatibility. Not used by ``to_shell()`` since
    Unit 003 (Issue #48) switched the output format to key=value with
    backslash/newline escaping (see ``_encode_value``).
    """
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")


def _encode_value(value: str) -> str:
    """Encode a value for the key=value shell envelope (Issue #48).

    Escape ``\\`` and ``LF`` only; everything else is emitted verbatim.
    Trailing newlines are stripped (ShellSafeString invariant: shell
    variables cannot represent trailing LF anyway).
    """
    if "\x00" in value:
        raise ValueError("NUL character is not allowed in config values")
    return value.rstrip("\n").replace("\\", "\\\\").replace("\n", "\\n")


def to_shell(config: dict) -> str:
    """Convert config dict to shell key=value envelope (Issue #48).

    Output format: one ``KEY=encoded_value`` per line. The shell side
    (``lib/config.sh::load_config``) decodes ``\\n`` -> LF and ``\\\\`` -> ``\\``
    using awk in a single scan, then ``export``s each entry. ``eval`` is
    no longer used.
    """
    lines = []
    for key, value in config.items():
        shell_key = key.upper()
        if not _SHELL_KEY_RE.match(shell_key):
            raise ValueError(
                f"invalid shell key after upper(): {shell_key!r} "
                f"(must match [A-Z][A-Z0-9_]*)"
            )
        if isinstance(value, list):
            shell_val = " ".join(value)
        elif isinstance(value, bool):
            shell_val = "1" if value else ""
        else:
            shell_val = str(value)
        lines.append(f"{shell_key}={_encode_value(shell_val)}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# TOML writing helpers
# ---------------------------------------------------------------------------

def write_toml_value(value) -> str:
    """Format a value for TOML output."""
    if isinstance(value, list):
        items = ", ".join(f'"{v}"' for v in value)
        return f"[{items}]"
    if isinstance(value, bool):
        return "true" if value else "false"
    return f'"{value}"'


def set_key_in_toml(path: Path, key: str, value, section: str = "global") -> None:
    """Set a key in the TOML file, preserving comments and structure."""
    lines = path.read_text().splitlines()
    toml_val = write_toml_value(value)
    target = f"{key} = {toml_val}"

    in_section = False
    replaced = False
    result = []

    for line in lines:
        stripped = line.strip()

        # Track current section
        if stripped.startswith("["):
            if in_section and not replaced:
                # End of target section without finding key — insert before next section
                result.append(target)
                replaced = True
            in_section = stripped == f"[{section}]"

        # Replace existing key in the right section
        if in_section and stripped.startswith(f"{key} ") or (in_section and stripped.startswith(f"{key}=")):
            result.append(target)
            replaced = True
            continue

        # Also handle commented-out version: # key = ...
        if in_section and stripped.startswith(f"# {key} ") and not replaced:
            result.append(target)
            replaced = True
            continue

        result.append(line)

    if not replaced:
        # Section exists but key wasn't found and we're still in it
        if in_section:
            result.append(target)
        else:
            # Section doesn't exist at all
            result.append("")
            result.append(f"[{section}]")
            result.append(target)

    path.write_text("\n".join(result) + "\n")


# ---------------------------------------------------------------------------
# Backward-compatible entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    from config_cli import main
    main()
