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
