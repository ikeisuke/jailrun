#!/usr/bin/env python3
"""jailrun legacy config migration."""

from __future__ import annotations

import copy
import sys
from pathlib import Path

from config import (
    DEFAULTS,
    LIST_KEYS,
    config_file,
    legacy_config_file,
)


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

            # GH_TOKEN_NAME takes precedence over legacy GH_KEYCHAIN_SERVICE
            if key == "GH_KEYCHAIN_SERVICE" and "gh_token_name" in values:
                continue

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
