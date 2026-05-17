#!/usr/bin/env python3
"""Unit tests for lib/proxy.py bind retry contract.

Covers the 4 retry-contract invariants deferred in v0.4.3 Unit 001
(Issue #94):

1. _scan_once absorbs only EADDRINUSE; other OSError raises immediately.
2. _bind_in_range succeeds after a retry-recoverable EADDRINUSE.
3. _bind_in_range preserves the last EADDRINUSE instance as
   RuntimeError.__cause__ when the attempt limit is reached.
4. _bind_in_range exits via "budget exhausted" without an extra sleep
   when the jitter would overrun _BIND_RETRY_TOTAL_BUDGET_MS.

See:
    .aidlc/cycles/v0.5.0/design-artifacts/domain-models/
        unit_002_proxy_retry_tests_domain_model.md
    .aidlc/cycles/v0.5.0/design-artifacts/logical-designs/
        unit_002_proxy_retry_tests_logical_design.md
"""

import errno
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

# Add lib/ to path so we can import proxy
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

import proxy  # noqa: E402


def _make_socket_mock(side_effects):
    """Build a callable that returns MagicMock sockets with bind side_effect.

    Each call returns a fresh MagicMock (proxy._scan_once allocates one
    socket per candidate port). bind.side_effect is shared so the queue
    advances across sockets, but we wrap it per-instance to allow close
    tracking.
    """
    queue = list(side_effects)

    def factory(*_args, **_kwargs):
        sock = MagicMock()

        def _bind(_addr):
            if not queue:
                raise AssertionError("bind queue exhausted")
            effect = queue.pop(0)
            if effect is None:
                return None
            raise effect

        sock.bind.side_effect = _bind
        return sock

    return factory


class TestScanOnceErrorClassification(unittest.TestCase):
    """Invariant 1 (immediate-raise side): non-EADDRINUSE OSError raises."""

    def test_eaccess_raises_immediately(self):
        """OSError(EACCES) must propagate from _scan_once without retry."""
        factory = _make_socket_mock([OSError(errno.EACCES, "Permission denied")])
        with patch("proxy.socket.socket", side_effect=factory):
            with self.assertRaises(OSError) as ctx:
                proxy._scan_once("127.0.0.1", 40000, 40001)
            self.assertEqual(ctx.exception.errno, errno.EACCES)

    def test_eaddrinuse_absorbed_returns_none(self):
        """OSError(EADDRINUSE) is absorbed and returned as (None, err)."""
        # range is [40000, 40001] -> 2 candidates, both EADDRINUSE
        einuse = OSError(errno.EADDRINUSE, "Address already in use")
        factory = _make_socket_mock([einuse, einuse])
        with patch("proxy.socket.socket", side_effect=factory):
            sock, err = proxy._scan_once("127.0.0.1", 40000, 40001)
        self.assertIsNone(sock)
        self.assertIsNotNone(err)
        self.assertEqual(err.errno, errno.EADDRINUSE)


class TestBindInRangeRetrySuccess(unittest.TestCase):
    """Invariant 1 (absorb-then-retry side): retry succeeds after EADDRINUSE."""

    @patch("proxy.time.sleep")
    @patch("proxy.random.randint", return_value=5)
    def test_retry_succeeds_after_one_eaddrinuse(self, _mock_randint, mock_sleep):
        # First scan: all candidates EADDRINUSE -> (None, err)
        # Second scan: first candidate succeeds
        einuse = OSError(errno.EADDRINUSE, "Address already in use")
        factory = _make_socket_mock([einuse, einuse, None])
        with patch("proxy.socket.socket", side_effect=factory):
            sock = proxy._bind_in_range("127.0.0.1", 40000, 40001)
        # Returned object is the MagicMock from factory
        self.assertIsNotNone(sock)
        self.assertTrue(hasattr(sock, "bind"))
        # Exactly one sleep between attempt 1 and attempt 2
        self.assertEqual(mock_sleep.call_count, 1)


class TestBindInRangeRetryLimitReached(unittest.TestCase):
    """Invariant 2 (cause chain) + invariant 4 (attempt-limit break)."""

    @patch("proxy.time.sleep")
    @patch("proxy.random.randint", return_value=5)
    def test_runtime_error_preserves_last_eaddrinuse_instance(
        self, _mock_randint, mock_sleep
    ):
        # MAX_ATTEMPTS = 3, range [40000, 40001] = 2 candidates per scan
        # -> 6 EADDRINUSE bind calls total
        einuse_instances = [
            OSError(errno.EADDRINUSE, f"in use #{i}") for i in range(6)
        ]
        factory = _make_socket_mock(list(einuse_instances))
        with patch("proxy.socket.socket", side_effect=factory):
            with self.assertRaises(RuntimeError) as ctx:
                proxy._bind_in_range("127.0.0.1", 40000, 40001)
        # Invariant 2: __cause__ is the *last* EADDRINUSE instance (same object)
        self.assertIs(ctx.exception.__cause__, einuse_instances[-1])
        # Invariant 4: reason indicates attempt-limit break (not budget)
        self.assertIn("retry limit reached", str(ctx.exception))
        # max_attempts - 1 = 2 sleeps between the 3 attempts
        self.assertEqual(mock_sleep.call_count, proxy._BIND_RETRY_MAX_ATTEMPTS - 1)


class TestBindInRangeBudgetExhausted(unittest.TestCase):
    """Invariant 3 (budget early-stop): no extra sleep on budget overrun."""

    @patch("proxy.time.sleep")
    @patch("proxy.random.randint", return_value=5)
    @patch.object(proxy, "_BIND_RETRY_TOTAL_BUDGET_MS", 1)
    def test_budget_exhausted_breaks_without_sleep(
        self, _mock_randint, mock_sleep
    ):
        # Strategy A: BUDGET=1ms patched, jitter=5ms -> 5 > 1 triggers
        # budget_exhausted on the first jitter calculation. The break
        # happens *before* time.sleep is called.
        einuse = OSError(errno.EADDRINUSE, "Address already in use")
        factory = _make_socket_mock([einuse, einuse, einuse, einuse])
        with patch("proxy.socket.socket", side_effect=factory):
            with self.assertRaises(RuntimeError) as ctx:
                proxy._bind_in_range("127.0.0.1", 40000, 40001)
        self.assertIn("budget exhausted", str(ctx.exception))
        # Invariant 3: sleep is *not* called when budget would overrun
        self.assertEqual(mock_sleep.call_count, 0)


if __name__ == "__main__":
    unittest.main()
