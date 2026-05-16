#!/bin/sh
# Single source of truth for the jailrun WSL2 network namespace topology.
# Sourced by scripts/wsl2-netns-setup.sh, scripts/wsl2-netns-teardown.sh and
# lib/sandbox.sh so the namespace name, veth pair names and host IP are
# defined in exactly one place. POSIX sh only: variable assignments, no
# side effects (no command execution, no output).

JAILRUN_NETNS_HOST_IP="10.200.0.1"
JAILRUN_NETNS_NAME="agentns"
JAILRUN_NETNS_VETH_HOST="veth-host"
JAILRUN_NETNS_VETH_AGENT="veth-agent"

# proxy bind port range (single SoT). Closed interval [START, END]
# matching the iptables --dport START:END semantics.
#   - consumed today: scripts/wsl2-netns-setup.sh (cycle v0.4.1 / Unit 001)
#   - to be consumed by: lib/sandbox.sh and lib/netns_const_loader.py
#     (cycle v0.4.1 / Unit 002 — proxy bind enforcement + Python consumer)
# Value validation (integer / 1..65535 / START <= END) is the consumer's
# responsibility; this file stays side-effect free (assignments only).
JAILRUN_PROXY_PORT_RANGE_START="60000"
JAILRUN_PROXY_PORT_RANGE_END="60099"
