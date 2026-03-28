#!/usr/bin/env python3
"""jailrun configuration CLI.

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

from config import (
    DEFAULTS,
    DEFAULT_TOML,
    KNOWN_KEYS,
    LIST_KEYS,
    config_dir,
    config_file,
    resolve_config,
    set_key_in_toml,
    to_shell,
)
from config_migrate import cmd_migrate


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
