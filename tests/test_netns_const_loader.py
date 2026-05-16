"""Unit tests for lib/netns_const_loader.load_port_range.

The loader resolves netns-const.sh strictly via ``__file__`` (cycle
v0.4.1 / Unit 002 code review R1 #2 — no environment-variable override
path), so the fixture tests monkeypatch the private
``_resolve_netns_const_path`` instead of touching the environment.
"""

from __future__ import annotations

import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "lib"))
sys.path.insert(0, str(REPO_ROOT / "tests"))

import netns_const_loader  # noqa: E402
from netns_const_loader import load_port_range  # noqa: E402
from port_range_invalid_vectors import INVALID_VECTORS  # noqa: E402


def _write_fixture(dirpath: Path, start: str, end: str) -> Path:
    sot = dirpath / "netns-const.sh"
    sot.write_text(
        textwrap.dedent(
            f"""\
            JAILRUN_NETNS_HOST_IP="10.200.0.1"
            JAILRUN_NETNS_NAME="agentns"
            JAILRUN_NETNS_VETH_HOST="veth-host"
            JAILRUN_NETNS_VETH_AGENT="veth-agent"
            JAILRUN_PROXY_PORT_RANGE_START="{start}"
            JAILRUN_PROXY_PORT_RANGE_END="{end}"
            """
        )
    )
    return sot


class LoadPortRangeTest(unittest.TestCase):
    # ---- happy path ----

    def test_resolves_via_file_relative_default(self) -> None:
        # __file__ relative resolves to lib/netns-const.sh in the repo,
        # which currently ships 60000/60099 as the SoT default.
        self.assertEqual(load_port_range(), (60000, 60099))

    def test_returns_fixture_values_when_path_patched(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sot = _write_fixture(Path(tmp), "60001", "60100")
            with patch.object(
                netns_const_loader, "_resolve_netns_const_path",
                return_value=sot,
            ):
                self.assertEqual(load_port_range(), (60001, 60100))

    # ---- missing file ----

    def test_missing_file_raises_with_resolved_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            missing = Path(tmp) / "netns-const.sh"
            with patch.object(
                netns_const_loader, "_resolve_netns_const_path",
                return_value=missing,
            ):
                with self.assertRaises(RuntimeError) as ctx:
                    load_port_range()
            msg = str(ctx.exception)
            self.assertIn("netns-const.sh not found", msg)
            self.assertIn(str(missing), msg)

    # ---- shared invalid vectors ----

    def test_invalid_vectors_raise_runtime_error(self) -> None:
        for raw_start, raw_end, label in INVALID_VECTORS:
            with self.subTest(label=label, start=raw_start, end=raw_end):
                with tempfile.TemporaryDirectory() as tmp:
                    sot = _write_fixture(Path(tmp), raw_start, raw_end)
                    with patch.object(
                        netns_const_loader, "_resolve_netns_const_path",
                        return_value=sot,
                    ):
                        with self.assertRaises(RuntimeError) as ctx:
                            load_port_range()
                    msg = str(ctx.exception)
                    # All errors must include the resolved SoT absolute
                    # path (contract I5 in the domain model).
                    self.assertIn(str(sot), msg)

    # ---- error message contract ----

    def test_error_message_includes_resolved_path_on_validation_failure(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sot = _write_fixture(Path(tmp), "abc", "60099")
            with patch.object(
                netns_const_loader, "_resolve_netns_const_path",
                return_value=sot,
            ):
                with self.assertRaises(RuntimeError) as ctx:
                    load_port_range()
            msg = str(ctx.exception)
            self.assertIn("invalid JAILRUN_PROXY_PORT_RANGE", msg)
            self.assertIn(str(sot), msg)

    # ---- module surface ----

    def test_module_exposes_only_load_port_range(self) -> None:
        # Domain model R1 #1 / R2 #1: public API is the function only.
        self.assertEqual(netns_const_loader.__all__, ["load_port_range"])


if __name__ == "__main__":
    unittest.main()
