#!/usr/bin/env python3
"""Unit tests for lib/proxy.py."""

import ipaddress
import os
import socket
import sys
import unittest
from unittest.mock import MagicMock, patch

# Add lib/ to path so we can import proxy
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

import proxy


class TestIsPrivateIp(unittest.TestCase):
    """Tests for is_private_ip()."""

    def test_rfc1918_10(self):
        self.assertTrue(proxy.is_private_ip("10.0.0.1"))
        self.assertTrue(proxy.is_private_ip("10.255.255.255"))

    def test_rfc1918_172(self):
        self.assertTrue(proxy.is_private_ip("172.16.0.1"))
        self.assertTrue(proxy.is_private_ip("172.31.255.255"))

    def test_rfc1918_192(self):
        self.assertTrue(proxy.is_private_ip("192.168.0.1"))
        self.assertTrue(proxy.is_private_ip("192.168.255.255"))

    def test_loopback(self):
        self.assertTrue(proxy.is_private_ip("127.0.0.1"))
        self.assertTrue(proxy.is_private_ip("127.255.255.255"))

    def test_link_local(self):
        self.assertTrue(proxy.is_private_ip("169.254.0.1"))
        self.assertTrue(proxy.is_private_ip("169.254.255.255"))

    def test_ipv6_loopback(self):
        self.assertTrue(proxy.is_private_ip("::1"))

    def test_ipv6_ula(self):
        self.assertTrue(proxy.is_private_ip("fc00::1"))
        self.assertTrue(proxy.is_private_ip("fd00::1"))

    def test_ipv6_link_local(self):
        self.assertTrue(proxy.is_private_ip("fe80::1"))

    def test_public_ipv4(self):
        self.assertFalse(proxy.is_private_ip("8.8.8.8"))
        self.assertFalse(proxy.is_private_ip("1.1.1.1"))
        self.assertFalse(proxy.is_private_ip("203.0.113.1"))

    def test_public_ipv6(self):
        self.assertFalse(proxy.is_private_ip("2001:4860:4860::8888"))

    def test_invalid_input(self):
        self.assertFalse(proxy.is_private_ip("not-an-ip"))
        self.assertFalse(proxy.is_private_ip(""))


class TestMatchDomain(unittest.TestCase):
    """Tests for match_domain()."""

    def test_exact_match(self):
        allowed = {"api.anthropic.com", "github.com"}
        self.assertTrue(proxy.match_domain("api.anthropic.com", allowed))
        self.assertTrue(proxy.match_domain("github.com", allowed))

    def test_no_match(self):
        allowed = {"api.anthropic.com"}
        self.assertFalse(proxy.match_domain("evil.com", allowed))

    def test_wildcard_match(self):
        allowed = {"*.example.com"}
        self.assertTrue(proxy.match_domain("sub.example.com", allowed))
        self.assertTrue(proxy.match_domain("deep.sub.example.com", allowed))

    def test_wildcard_no_match_base(self):
        allowed = {"*.example.com"}
        self.assertFalse(proxy.match_domain("example.com", allowed))

    def test_case_insensitive(self):
        allowed = {"api.anthropic.com"}
        self.assertTrue(proxy.match_domain("API.Anthropic.COM", allowed))

    def test_empty_allowed(self):
        self.assertFalse(proxy.match_domain("anything.com", set()))


class TestHandleClient(unittest.TestCase):
    """Tests for handle_client() using mock sockets."""

    def _make_client(self, request_line):
        """Create a mock client socket that returns a CONNECT request."""
        client = MagicMock()
        request = f"{request_line}\r\nHost: target\r\n\r\n".encode()
        client.recv.side_effect = [request, b""]
        return client

    def _get_response(self, client):
        """Extract HTTP response line from sendall calls."""
        for call in client.sendall.call_args_list:
            data = call[0][0]
            if isinstance(data, bytes) and data.startswith(b"HTTP/"):
                return data.split(b"\r\n")[0].decode()
        return None

    def test_non_connect_method_returns_405(self):
        client = self._make_client("GET http://evil.com/ HTTP/1.1")
        proxy.handle_client(client, ("127.0.0.1", 12345), {"example.com"})
        self.assertEqual(self._get_response(client), "HTTP/1.1 405 Method Not Allowed")

    def test_malformed_request_returns_400(self):
        client = self._make_client("INVALID")
        proxy.handle_client(client, ("127.0.0.1", 12345), {"example.com"})
        self.assertEqual(self._get_response(client), "HTTP/1.1 400 Bad Request")

    def test_blocked_domain_returns_403(self):
        client = self._make_client("CONNECT evil.com:443 HTTP/1.1")
        proxy.handle_client(client, ("127.0.0.1", 12345), {"good.com"})
        resp = self._get_response(client)
        self.assertEqual(resp, "HTTP/1.1 403 Forbidden")

    @patch("proxy.socket.getaddrinfo", side_effect=socket.gaierror("DNS fail"))
    def test_dns_failure_returns_502(self, _mock_dns):
        client = self._make_client("CONNECT allowed.com:443 HTTP/1.1")
        proxy.handle_client(client, ("127.0.0.1", 12345), {"allowed.com"})
        self.assertEqual(self._get_response(client), "HTTP/1.1 502 Bad Gateway")

    @patch("proxy.socket.getaddrinfo")
    def test_private_ip_resolution_returns_403(self, mock_dns):
        mock_dns.return_value = [
            (socket.AF_INET, socket.SOCK_STREAM, 0, "", ("10.0.0.1", 443)),
        ]
        client = self._make_client("CONNECT allowed.com:443 HTTP/1.1")
        proxy.handle_client(client, ("127.0.0.1", 12345), {"allowed.com"})
        self.assertEqual(self._get_response(client), "HTTP/1.1 403 Forbidden")

    @patch("proxy.socket.socket")
    @patch("proxy.socket.getaddrinfo")
    def test_valid_connect_returns_200(self, mock_dns, mock_socket_cls):
        mock_dns.return_value = [
            (socket.AF_INET, socket.SOCK_STREAM, 0, "", ("93.184.216.34", 443)),
        ]
        mock_remote = MagicMock()
        mock_socket_cls.return_value = mock_remote

        client = self._make_client("CONNECT example.com:443 HTTP/1.1")
        # Make relay exit quickly
        mock_remote.recv.return_value = b""
        proxy.handle_client(client, ("127.0.0.1", 12345), {"example.com"})
        self.assertEqual(self._get_response(client), "HTTP/1.1 200 Connection Established")

    @patch("proxy.socket.getaddrinfo")
    def test_all_connection_attempts_fail_returns_502(self, mock_dns):
        mock_dns.return_value = [
            (socket.AF_INET, socket.SOCK_STREAM, 0, "", ("93.184.216.34", 443)),
        ]
        client = self._make_client("CONNECT example.com:443 HTTP/1.1")
        with patch("proxy.socket.socket") as mock_socket_cls:
            mock_socket_cls.return_value.connect.side_effect = OSError("refused")
            proxy.handle_client(client, ("127.0.0.1", 12345), {"example.com"})
        self.assertEqual(self._get_response(client), "HTTP/1.1 502 Bad Gateway")

    def test_invalid_port_returns_400(self):
        client = self._make_client("CONNECT example.com:notaport HTTP/1.1")
        proxy.handle_client(client, ("127.0.0.1", 12345), {"example.com"})
        self.assertEqual(self._get_response(client), "HTTP/1.1 400 Bad Request")

    def test_connect_without_port_defaults_443(self):
        """CONNECT with host only (no port) should default to 443."""
        client = self._make_client("CONNECT example.com HTTP/1.1")
        with patch("proxy.socket.getaddrinfo") as mock_dns, \
             patch("proxy.socket.socket") as mock_socket_cls:
            mock_dns.return_value = [
                (socket.AF_INET, socket.SOCK_STREAM, 0, "", ("93.184.216.34", 443)),
            ]
            mock_remote = MagicMock()
            mock_socket_cls.return_value = mock_remote
            mock_remote.recv.return_value = b""
            proxy.handle_client(client, ("127.0.0.1", 12345), {"example.com"})
        mock_dns.assert_called_once_with("example.com", 443, socket.AF_UNSPEC, socket.SOCK_STREAM)


if __name__ == "__main__":
    unittest.main()
