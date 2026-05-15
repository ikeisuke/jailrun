#!/bin/bash
# Tear down the jailrun WSL2 network namespace.
# Usage: sudo scripts/wsl2-netns-teardown.sh
# Idempotent — safe to run multiple times, including when nothing exists or
# when a previous setup failed partway through (partial residue is cleaned up).
#
# Removes the "agentns" network namespace and the "veth-host" link created by
# scripts/wsl2-netns-setup.sh.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "error: must be run as root (sudo $0)" >&2
  exit 1
fi

# --- netns topology constants (single source of truth) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NETNS_CONST="$SCRIPT_DIR/../lib/netns-const.sh"
if [ ! -f "$NETNS_CONST" ]; then
  echo "error: netns constants not found: $NETNS_CONST" >&2
  exit 1
fi
. "$NETNS_CONST"
if [ -z "${JAILRUN_NETNS_NAME:-}" ] || [ -z "${JAILRUN_NETNS_VETH_HOST:-}" ]; then
  echo "error: netns constants incomplete in $NETNS_CONST" >&2
  exit 1
fi

NS="$JAILRUN_NETNS_NAME"
VETH_HOST="$JAILRUN_NETNS_VETH_HOST"

# --- Namespace ---
if ip netns list | grep -qw "$NS"; then
  ip netns del "$NS"
  echo "[netns] deleted '$NS'"
else
  echo "[netns] '$NS' not found, skipping"
fi

# --- Veth pair ---
# Deleting the namespace removes veth-agent and, with it, the veth pair.
# veth-host may still remain if setup failed before the peer was moved into
# the namespace — delete it independently so partial residue is cleaned up.
if ip link show "$VETH_HOST" &>/dev/null; then
  ip link del "$VETH_HOST"
  echo "[veth] deleted '$VETH_HOST'"
else
  echo "[veth] '$VETH_HOST' not found, skipping"
fi

echo "[done] namespace '$NS' torn down"
