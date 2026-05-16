#!/bin/bash
# Setup network namespace for jailrun on WSL2.
# Usage: sudo scripts/wsl2-netns-setup.sh
# Idempotent — safe to run multiple times.
#
# Creates a network namespace "agentns" with a veth pair so that processes
# inside can only reach the proxy at 10.200.0.1 on the configured TCP port
# range (JAILRUN_PROXY_PORT_RANGE_START:JAILRUN_PROXY_PORT_RANGE_END).

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
if [ -z "${JAILRUN_NETNS_NAME:-}" ] || [ -z "${JAILRUN_NETNS_VETH_HOST:-}" ] \
  || [ -z "${JAILRUN_NETNS_VETH_AGENT:-}" ] || [ -z "${JAILRUN_NETNS_HOST_IP:-}" ]; then
  echo "error: netns constants incomplete in $NETNS_CONST" >&2
  exit 1
fi

if [ -z "${JAILRUN_PROXY_PORT_RANGE_START:-}" ] || [ -z "${JAILRUN_PROXY_PORT_RANGE_END:-}" ]; then
  echo "error: netns constants incomplete in $NETNS_CONST" >&2
  exit 1
fi

# Validate that the SoT port range satisfies the contract documented in
# lib/netns-const.sh: decimal integer without leading zeros / 1..65535 /
# START <= END. lib/netns-const.sh is intentionally assignment-only, so
# verification lives on the consumer.
_range_invalid=0
for _range_value in "$JAILRUN_PROXY_PORT_RANGE_START" "$JAILRUN_PROXY_PORT_RANGE_END"; do
  case "$_range_value" in
    ''|*[!0-9]*|0|0[0-9]*) _range_invalid=1 ;;
  esac
done
if [ "$_range_invalid" -eq 1 ] \
  || [ "$JAILRUN_PROXY_PORT_RANGE_START" -lt 1 ] \
  || [ "$JAILRUN_PROXY_PORT_RANGE_END" -gt 65535 ] \
  || [ "$JAILRUN_PROXY_PORT_RANGE_START" -gt "$JAILRUN_PROXY_PORT_RANGE_END" ]; then
  echo "error: JAILRUN_PROXY_PORT_RANGE_START / _END must be integers in 1..65535 with START <= END (got START=$JAILRUN_PROXY_PORT_RANGE_START, END=$JAILRUN_PROXY_PORT_RANGE_END)" >&2
  exit 1
fi
unset _range_invalid _range_value

NS="$JAILRUN_NETNS_NAME"
VETH_HOST="$JAILRUN_NETNS_VETH_HOST"
VETH_AGENT="$JAILRUN_NETNS_VETH_AGENT"
HOST_IP="$JAILRUN_NETNS_HOST_IP"
PORT_RANGE_START="$JAILRUN_PROXY_PORT_RANGE_START"
PORT_RANGE_END="$JAILRUN_PROXY_PORT_RANGE_END"
AGENT_IP="10.200.0.2"
CIDR="24"

# --- Namespace ---
if ip netns list | grep -qw "$NS"; then
  echo "[netns] '$NS' already exists, skipping creation"
else
  ip netns add "$NS"
  echo "[netns] created '$NS'"
fi

# --- Veth pair ---
if ip link show "$VETH_HOST" &>/dev/null; then
  echo "[veth] '$VETH_HOST' already exists, skipping"
else
  ip link add "$VETH_HOST" type veth peer name "$VETH_AGENT"
  ip link set "$VETH_AGENT" netns "$NS"
  echo "[veth] created $VETH_HOST <-> $VETH_AGENT"
fi

# --- Host side ---
if ! ip addr show "$VETH_HOST" | grep -q "$HOST_IP"; then
  ip addr add "$HOST_IP/$CIDR" dev "$VETH_HOST"
fi
ip link set "$VETH_HOST" up

# --- Agent side (inside namespace) ---
ip netns exec "$NS" ip addr add "$AGENT_IP/$CIDR" dev "$VETH_AGENT" 2>/dev/null || true
ip netns exec "$NS" ip link set lo up
ip netns exec "$NS" ip link set "$VETH_AGENT" up
ip netns exec "$NS" ip route replace default via "$HOST_IP"

# --- iptables (inside namespace) ---
# OUTPUT: default DROP, allow loopback and TCP to the proxy host IP on the
# configured port range only (defense-in-depth — see lib/netns-const.sh and
# .aidlc/cycles/v0.4.1/requirements/intent.md M1/M2 for the SoT contract).
ip netns exec "$NS" iptables -P OUTPUT DROP
ip netns exec "$NS" iptables -F OUTPUT
ip netns exec "$NS" iptables -A OUTPUT -o lo -j ACCEPT
ip netns exec "$NS" iptables -A OUTPUT -p tcp -d "$HOST_IP" \
  --dport "$PORT_RANGE_START":"$PORT_RANGE_END" -j ACCEPT
# INPUT: default DROP, allow loopback and replies to agent-initiated flows.
# Blocks unrelated host->agent direct connections (e.g. from 10.200.0.1).
ip netns exec "$NS" iptables -P INPUT DROP
ip netns exec "$NS" iptables -F INPUT
ip netns exec "$NS" iptables -A INPUT -i lo -j ACCEPT
ip netns exec "$NS" iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

echo "[done] namespace '$NS' ready — proxy binds to $HOST_IP ports $PORT_RANGE_START:$PORT_RANGE_END"
