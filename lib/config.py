#!/usr/bin/env python3
"""jailrun configuration API (TOML-based).

This module provides the core configuration loading, merging, and writing
functionality. For the CLI interface, see config_cli.py.
"""

from __future__ import annotations

import os
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
    dir_conf = {}
    if directory and "dir" in raw:
        # Find matching dir (exact match or longest prefix)
        best_match = ""
        for dir_key in raw["dir"]:
            if directory == dir_key or directory.startswith(dir_key.rstrip("/") + "/"):
                if len(dir_key) > len(best_match):
                    best_match = dir_key
        if best_match:
            dir_conf = raw["dir"][best_match]
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

    return result


# ---------------------------------------------------------------------------
# Shell output
# ---------------------------------------------------------------------------

def shell_escape(value: str) -> str:
    """Escape a string for safe embedding in double-quoted shell context."""
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")


def to_shell(config: dict) -> str:
    """Convert config dict to shell-eval format (KEY="value")."""
    lines = []
    # Map TOML keys to shell variable names (uppercase)
    for key, value in config.items():
        shell_key = key.upper()
        if isinstance(value, list):
            shell_val = " ".join(value)
        elif isinstance(value, bool):
            shell_val = "1" if value else ""
        else:
            shell_val = str(value)
        lines.append(f'{shell_key}="{shell_escape(shell_val)}"')
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
