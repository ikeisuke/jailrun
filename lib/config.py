#!/usr/bin/env python3
"""jailrun configuration manager (TOML-based).

Subcommands:
    load   --app NAME --dir PATH   Merge config and output shell-eval format
    show                            Display current config values
    set    KEY VALUE                Update a config key
    set    --append KEY VALUE       Add a value to a list key
    set    --remove KEY VALUE       Remove a value from a list key
    edit                            Open config in $EDITOR
    path                            Print config file path
    init   [--force]                Generate default config
    migrate                         Convert legacy shell config to TOML
"""

from __future__ import annotations

import os
import sys
import copy
import subprocess
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
    "sandbox_extra_deny_read": [],
    "sandbox_extra_allow_write": [],
    "sandbox_extra_allow_write_files": [],
    "sandbox_passthrough_env": [],
}

LIST_KEYS = {
    "allowed_aws_profiles",
    "sandbox_extra_deny_read",
    "sandbox_extra_allow_write",
    "sandbox_extra_allow_write_files",
    "sandbox_passthrough_env",
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

# additional read-deny paths (default: ~/.aws ~/.ssh ~/.gnupg ~/.config/gh)
# sandbox_extra_deny_read = []

# additional write-allow paths (default: ~/.claude ~/.codex ~/.kiro etc.)
# sandbox_extra_allow_write = []

# additional write-allow files
# sandbox_extra_allow_write_files = []

# environment variables to pass through to sandbox
# sandbox_passthrough_env = ["ANTHROPIC_API_KEY"]

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
    """Load and merge config layers: defaults -> global -> profile -> app -> dir."""
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

    # Layer 2: [app.<name>] -> resolve profile
    if app and "app" in raw and app in raw["app"]:
        app_conf = raw["app"][app]
        if "profile" in app_conf:
            profile_name = app_conf["profile"]
        # App-level settings (non-profile) append to lists
        app_settings = {k: v for k, v in app_conf.items() if k != "profile"}
        if app_settings:
            result = merge_layer(result, app_settings, append_lists=True)

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

    # Layer 5: Apply dir settings (non-profile) — appends to lists
    if dir_conf:
        dir_settings = {k: v for k, v in dir_conf.items() if k != "profile"}
        if dir_settings:
            result = merge_layer(result, dir_settings, append_lists=True)

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
# Migration from legacy shell config
# ---------------------------------------------------------------------------

def migrate_shell_to_toml(shell_path: Path) -> str:
    """Parse legacy shell config and produce TOML."""
    values: dict = {}
    with open(shell_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # Handle: export KEY="value" or KEY="value" or KEY=value
            if line.startswith("export "):
                line = line[7:].strip()
            if "=" not in line:
                continue
            key, _, val = line.partition("=")
            key = key.strip()
            val = val.strip().strip('"').strip("'")

            # Map legacy keys
            key_map = {
                "GH_KEYCHAIN_SERVICE": "gh_token_name",
                "GH_TOKEN_NAME": "gh_token_name",
                "ALLOWED_AWS_PROFILES": "allowed_aws_profiles",
                "DEFAULT_AWS_PROFILE": "default_aws_profile",
                "SANDBOX_EXTRA_DENY_READ": "sandbox_extra_deny_read",
                "SANDBOX_EXTRA_ALLOW_WRITE": "sandbox_extra_allow_write",
                "SANDBOX_EXTRA_ALLOW_WRITE_FILES": "sandbox_extra_allow_write_files",
                "SANDBOX_PASSTHROUGH_ENV": "sandbox_passthrough_env",
            }
            toml_key = key_map.get(key)
            if toml_key is None:
                continue

            # Handle GH_KEYCHAIN_SERVICE github: prefix
            if key == "GH_KEYCHAIN_SERVICE" and val.startswith("github:"):
                val = val[7:]

            if toml_key in LIST_KEYS:
                values[toml_key] = val.split() if val else []
            else:
                values[toml_key] = val

    # Build TOML
    lines = [
        "# jailrun config (migrated from shell format)",
        "# Docs: https://github.com/ikeisuke/jailrun",
        "",
        "[global]",
    ]
    merged = copy.deepcopy(DEFAULTS)
    merged.update(values)

    for key in DEFAULTS:
        val = merged[key]
        if isinstance(val, list):
            items = ", ".join(f'"{v}"' for v in val)
            lines.append(f'{key} = [{items}]')
        else:
            lines.append(f'{key} = "{val}"')

    lines.append("")
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
# CLI commands
# ---------------------------------------------------------------------------

def cmd_load(args: list[str]) -> None:
    app = ""
    directory = ""
    i = 0
    while i < len(args):
        if args[i] == "--app" and i + 1 < len(args):
            app = args[i + 1]
            i += 2
        elif args[i] == "--dir" and i + 1 < len(args):
            directory = args[i + 1]
            i += 2
        else:
            i += 1

    conf = resolve_config(app=app, directory=directory)
    print(to_shell(conf))


def cmd_show(args: list[str]) -> None:
    path = config_file()
    if not path.exists():
        print(f"[config] no config file found: {path}", file=sys.stderr)
        print("[config] run 'jailrun config init' to create one", file=sys.stderr)
        sys.exit(1)

    conf = resolve_config()
    for key in sorted(conf):
        val = conf[key]
        if isinstance(val, list):
            print(f"{key} = {val}")
        else:
            print(f'{key} = "{val}"')


def cmd_set(args: list[str]) -> None:
    path = config_file()
    if not path.exists():
        print(f"[config] no config file found: {path}", file=sys.stderr)
        sys.exit(1)

    mode = "replace"
    rest = []
    for arg in args:
        if arg == "--append":
            mode = "append"
        elif arg == "--remove":
            mode = "remove"
        else:
            rest.append(arg)

    if len(rest) < 1:
        print("[config] ERROR: missing KEY", file=sys.stderr)
        sys.exit(1)

    key = rest[0]
    if key not in KNOWN_KEYS:
        print(f"[config] ERROR: unknown key '{key}'", file=sys.stderr)
        print(f"[config] known keys: {', '.join(sorted(KNOWN_KEYS))}", file=sys.stderr)
        sys.exit(1)

    if mode != "replace" and key not in LIST_KEYS:
        print(f"[config] ERROR: --{mode} is only supported for list-type keys", file=sys.stderr)
        sys.exit(1)

    if mode == "replace":
        if len(rest) < 2:
            print("[config] ERROR: missing VALUE", file=sys.stderr)
            sys.exit(1)
        value = rest[1]
        if key in LIST_KEYS:
            set_key_in_toml(path, key, value.split())
        else:
            set_key_in_toml(path, key, value)
    elif mode == "append":
        if len(rest) < 2:
            print("[config] ERROR: missing VALUE", file=sys.stderr)
            sys.exit(1)
        value = rest[1]
        conf = resolve_config()
        current = conf.get(key, [])
        if value in current:
            print(f"[config] '{value}' already in {key}", file=sys.stderr)
            return
        current.append(value)
        set_key_in_toml(path, key, current)
    elif mode == "remove":
        if len(rest) < 2:
            print("[config] ERROR: missing VALUE", file=sys.stderr)
            sys.exit(1)
        value = rest[1]
        conf = resolve_config()
        current = conf.get(key, [])
        current = [v for v in current if v != value]
        set_key_in_toml(path, key, current)


def cmd_edit(args: list[str]) -> None:
    path = config_file()
    if not path.exists():
        print(f"[config] no config file found: {path}", file=sys.stderr)
        sys.exit(1)
    editor = os.environ.get("EDITOR", "vi")
    os.execvp(editor, [editor, str(path)])


def cmd_path(args: list[str]) -> None:
    print(config_file())


def cmd_init(args: list[str]) -> None:
    force = "--force" in args
    path = config_file()

    if path.exists() and not force:
        print(f"[config] config already exists: {path}", file=sys.stderr)
        print("[config] use --force to overwrite", file=sys.stderr)
        sys.exit(1)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(DEFAULT_TOML)
    print(f"[config] created: {path}")


def cmd_migrate(args: list[str]) -> None:
    legacy = legacy_config_file()
    toml_path = config_file()

    if not legacy.exists():
        print(f"[config] no legacy config found: {legacy}", file=sys.stderr)
        sys.exit(1)

    if toml_path.exists() and "--force" not in args:
        print(f"[config] TOML config already exists: {toml_path}", file=sys.stderr)
        print("[config] use --force to overwrite", file=sys.stderr)
        sys.exit(1)

    toml_content = migrate_shell_to_toml(legacy)
    toml_path.parent.mkdir(parents=True, exist_ok=True)
    toml_path.write_text(toml_content + "\n")
    print(f"[config] migrated: {legacy} -> {toml_path}")
    print(f"[config] review the new config: {toml_path}")
    print(f"[config] you can remove the old config: {legacy}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]
    args = sys.argv[2:]

    commands = {
        "load": cmd_load,
        "show": cmd_show,
        "set": cmd_set,
        "edit": cmd_edit,
        "path": cmd_path,
        "init": cmd_init,
        "migrate": cmd_migrate,
    }

    if cmd in ("--help", "-h"):
        print(__doc__)
        sys.exit(0)

    if cmd not in commands:
        print(f"[config] ERROR: unknown subcommand '{cmd}'", file=sys.stderr)
        sys.exit(1)

    commands[cmd](args)


if __name__ == "__main__":
    main()
