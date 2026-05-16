#!/usr/bin/env python3
"""jailrun HTTPS CONNECT proxy with domain allowlist.

Lightweight forward proxy that only allows HTTPS CONNECT to approved domains.
No TLS termination or certificates needed — filtering is based on the
CONNECT host header.

Usage:
    python3 proxy.py --allow-domains "api.anthropic.com,github.com" [--port 0]

The proxy prints the listening port to stdout on startup, then logs to stderr.

Cycle v0.4.1 introduces an optional ``--enforce-port-range`` flag that
locks the bind to the SoT range in ``lib/netns-const.sh``
(``JAILRUN_PROXY_PORT_RANGE_START..END``). The flag is **off** by default
so plain ``127.0.0.1`` callers (no WSL2 netns) keep the full OS ephemeral
range and concurrent local jailrun runs do not contend for a 100-port
window. ``lib/sandbox.sh`` passes ``--enforce-port-range`` only when the
``agentns`` namespace is active (i.e. when the netns OUTPUT iptables
``--dport`` rule actually constrains traffic).

When ``--enforce-port-range`` is set:

- ``--port N`` with N outside [START, END] is rejected (fail-closed)
- ``--port 0`` (default) does NOT fall back to OS ephemeral ports; the
  proxy scans [START, END] sequentially and binds the first available
  port

When the flag is **not** set, the proxy uses the unrestricted bind
behaviour from v0.4.0.
"""

from __future__ import annotations

import argparse
import ipaddress
import logging
import select
import socket
import sys
import threading

from netns_const_loader import load_port_range

logger = logging.getLogger("jailrun-proxy")

# RFC1918 + link-local + loopback + metadata endpoints
BLOCKED_IP_RANGES = [
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
    ipaddress.ip_network("169.254.0.0/16"),
    ipaddress.ip_network("127.0.0.0/8"),
    ipaddress.ip_network("::1/128"),
    ipaddress.ip_network("fc00::/7"),
    ipaddress.ip_network("fe80::/10"),
]


def is_private_ip(addr: str) -> bool:
    """Check if an IP address is in a private/reserved range."""
    try:
        ip = ipaddress.ip_address(addr)
        return any(ip in net for net in BLOCKED_IP_RANGES)
    except ValueError:
        return False


def match_domain(host: str, allowed: set[str]) -> bool:
    """Check if host matches any allowed domain (exact or wildcard)."""
    host = host.lower()
    if host in allowed:
        return True
    # Check wildcard: *.example.com matches sub.example.com
    parts = host.split(".")
    for i in range(1, len(parts)):
        wildcard = "*." + ".".join(parts[i:])
        if wildcard in allowed:
            return True
    return False


def relay(src: socket.socket, dst: socket.socket) -> None:
    """Relay data between two sockets until one closes."""
    try:
        while True:
            readable, _, _ = select.select([src, dst], [], [], 30)
            if not readable:
                continue
            for s in readable:
                data = s.recv(65536)
                if not data:
                    return
                other = dst if s is src else src
                other.sendall(data)
    except (OSError, BrokenPipeError):
        pass


def handle_client(
    client: socket.socket,
    addr: tuple,
    allowed_domains: set[str],
) -> None:
    """Handle a single client connection."""
    try:
        client.settimeout(30)
        # Read the request line and headers
        buf = b""
        while b"\r\n\r\n" not in buf and len(buf) < 8192:
            chunk = client.recv(4096)
            if not chunk:
                return
            buf += chunk

        request_line = buf.split(b"\r\n")[0].decode("utf-8", errors="replace")
        parts = request_line.split()

        if len(parts) < 2:
            client.sendall(b"HTTP/1.1 400 Bad Request\r\n\r\n")
            return

        method = parts[0].upper()

        # Only allow CONNECT (HTTPS tunneling)
        if method != "CONNECT":
            logger.warning("BLOCKED non-CONNECT: %s from %s", request_line, addr[0])
            client.sendall(b"HTTP/1.1 405 Method Not Allowed\r\n\r\n")
            return

        # Parse host:port from CONNECT target
        target = parts[1]
        if ":" in target:
            host, port_str = target.rsplit(":", 1)
            try:
                port = int(port_str)
            except ValueError:
                client.sendall(b"HTTP/1.1 400 Bad Request\r\n\r\n")
                return
        else:
            host = target
            port = 443

        # Check domain allowlist
        if not match_domain(host, allowed_domains):
            logger.warning("BLOCKED domain: %s from %s", host, addr[0])
            client.sendall(
                f"HTTP/1.1 403 Forbidden\r\nX-Blocked-Domain: {host}\r\n\r\n".encode()
            )
            return

        # Resolve and check for private IPs (DNS rebinding protection)
        try:
            addrinfos = socket.getaddrinfo(host, port, socket.AF_UNSPEC, socket.SOCK_STREAM)
        except socket.gaierror:
            logger.warning("BLOCKED dns-fail: %s from %s", host, addr[0])
            client.sendall(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
            return

        # Filter out private IPs
        safe_addrs = []
        for family, socktype, proto, canonname, sockaddr in addrinfos:
            ip = sockaddr[0]
            if is_private_ip(ip):
                logger.warning("BLOCKED private-ip: %s -> %s from %s", host, ip, addr[0])
            else:
                safe_addrs.append((family, socktype, proto, canonname, sockaddr))

        if not safe_addrs:
            client.sendall(b"HTTP/1.1 403 Forbidden\r\n\r\n")
            return

        # Connect to target
        remote = None
        for family, socktype, proto, canonname, sockaddr in safe_addrs:
            try:
                remote = socket.socket(family, socktype, proto)
                remote.settimeout(30)
                remote.connect(sockaddr)
                break
            except OSError:
                if remote:
                    remote.close()
                remote = None

        if remote is None:
            client.sendall(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
            return

        # Send 200 Connection Established
        client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        logger.info("CONNECT %s:%d from %s", host, port, addr[0])

        # Relay traffic
        client.settimeout(None)
        remote.settimeout(None)
        relay(client, remote)
        remote.close()

    except Exception:
        logger.debug("connection error from %s", addr[0], exc_info=True)
    finally:
        try:
            client.close()
        except OSError:
            pass


def _bind_in_range(bind: str, start: int, end: int) -> socket.socket:
    """Try sequential bind across [start, end] and return the first success.

    Mirrors the iptables --dport START:END contract from cycle v0.4.1 /
    Unit 001: the proxy must never bind outside the SoT range, so the
    ephemeral path does NOT fall back to OS-assigned ports.
    """
    last_error: OSError | None = None
    for candidate in range(start, end + 1):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind((bind, candidate))
            return sock
        except OSError as exc:
            last_error = exc
            sock.close()
            continue
    tried = end - start + 1
    raise RuntimeError(
        f"failed to bind to any port in range [{start}, {end}] "
        f"(tried {tried}, last error: {last_error})"
    )


def run_proxy(
    allowed_domains: set[str],
    port: int = 0,
    bind: str = "127.0.0.1",
    enforce_port_range: bool = False,
) -> None:
    """Start the proxy server.

    When ``enforce_port_range`` is True, the bind is constrained to the SoT
    range from ``lib/netns-const.sh`` (matching the WSL2 netns iptables
    ``--dport`` rule). When False (default), the bind uses the unrestricted
    v0.4.0 behaviour — ``port`` is passed straight to ``bind()`` so
    ``--port 0`` resolves via the OS ephemeral pool.
    """
    if enforce_port_range:
        start, end = load_port_range()

        if port == 0:
            server = _bind_in_range(bind, start, end)
        else:
            if port < start or port > end:
                raise RuntimeError(
                    f"requested port {port} is outside the configured proxy "
                    f"port range [{start}, {end}]"
                )
            server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind((bind, port))
    else:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((bind, port))

    server.listen(128)

    actual_port = server.getsockname()[1]

    # Print port to stdout for jailrun to read, then flush
    print(actual_port, flush=True)

    logger.info(
        "proxy listening on %s:%d, allowed: %s",
        bind,
        actual_port,
        ", ".join(sorted(allowed_domains)),
    )

    try:
        while True:
            client, addr = server.accept()
            t = threading.Thread(
                target=handle_client,
                args=(client, addr, allowed_domains),
                daemon=True,
            )
            t.start()
    except KeyboardInterrupt:
        pass
    finally:
        server.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="jailrun HTTPS CONNECT proxy")
    parser.add_argument(
        "--allow-domains",
        required=True,
        help="Comma-separated list of allowed domains (supports *.example.com wildcards)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=0,
        help="Port to listen on (0 = ephemeral)",
    )
    parser.add_argument(
        "--bind",
        default="127.0.0.1",
        help="Address to bind to (default: 127.0.0.1)",
    )
    parser.add_argument(
        "--enforce-port-range",
        action="store_true",
        help=(
            "Restrict bind to JAILRUN_PROXY_PORT_RANGE_START..END from "
            "lib/netns-const.sh (default: off; used by sandbox.sh when "
            "agentns is active to match the iptables --dport rule)"
        ),
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="[jailrun-proxy] %(levelname)s: %(message)s",
        stream=sys.stderr,
    )

    allowed = {d.strip().lower() for d in args.allow_domains.split(",") if d.strip()}
    if not allowed:
        logger.error("no allowed domains specified")
        sys.exit(1)

    try:
        run_proxy(allowed, args.port, args.bind, args.enforce_port_range)
    except RuntimeError as exc:
        logger.error("%s", exc)
        sys.exit(1)


if __name__ == "__main__":
    main()
