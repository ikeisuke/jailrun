#!/bin/sh
# Config management command (delegates to config.py)
# Usage: jailrun config <subcommand> [options]

set -eu

# resolve lib dir (works both in dev and after make install)
_LIB_DIR="$(cd "$(dirname "$0")" && pwd)"

exec python3 "$_LIB_DIR/config_cli.py" "$@"
