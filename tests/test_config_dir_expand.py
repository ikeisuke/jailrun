#!/usr/bin/env python3
"""Unit tests for resolve_config dir key expansion (Unit 003 / Issue #55)."""

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

import config  # noqa: E402


class DirKeyExpansionTests(unittest.TestCase):
    """resolve_config() must expand ~ and $VAR in [dir."..."] keys."""

    def setUp(self):
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.config_path = Path(self._tmpdir.name) / "config.toml"
        p = patch("config.config_file", return_value=self.config_path)
        p.start()
        self.addCleanup(p.stop)

    def _write(self, toml_text: str) -> None:
        self.config_path.write_text(toml_text)

    def test_tilde_expansion_matches(self):
        # `[dir."~/proj"]` should match a directory under the user's HOME.
        home = str(Path.home())
        self._write(
            '[profile.p]\n'
            'sandbox_passthrough_env = ["TILDE"]\n'
            '\n'
            '[dir."~/proj"]\n'
            'profile = "p"\n'
        )
        result = config.resolve_config(directory=f"{home}/proj/sub")
        self.assertIn("TILDE", result.get("sandbox_passthrough_env", []))

    def test_envvar_expansion_matches(self):
        # `[dir."$HOME/proj"]` should match a directory under HOME.
        home = str(Path.home())
        self._write(
            '[profile.p]\n'
            'sandbox_passthrough_env = ["DOLLAR"]\n'
            '\n'
            '[dir."$HOME/proj"]\n'
            'profile = "p"\n'
        )
        result = config.resolve_config(directory=f"{home}/proj")
        self.assertIn("DOLLAR", result.get("sandbox_passthrough_env", []))

    def test_absolute_path_backcompat(self):
        # Existing absolute-path keys must continue to match (no expansion changes them).
        self._write(
            '[profile.p]\n'
            'sandbox_passthrough_env = ["ABS"]\n'
            '\n'
            '[dir."/tmp/proj"]\n'
            'profile = "p"\n'
        )
        result = config.resolve_config(directory="/tmp/proj/sub")
        self.assertIn("ABS", result.get("sandbox_passthrough_env", []))

    def test_undefined_envvar_does_not_falsematch(self):
        # `$UNDEFINED_VAR/...` must not match the literal string in the cwd.
        self._write(
            '[profile.p]\n'
            'sandbox_passthrough_env = ["BAD"]\n'
            '\n'
            '[dir."$JAILRUN_UNDEFINED_TEST_VAR_42/proj"]\n'
            'profile = "p"\n'
        )
        # Ensure env var is not set, then pass a directory that, if matched
        # literally, would activate the profile.
        os.environ.pop("JAILRUN_UNDEFINED_TEST_VAR_42", None)
        result = config.resolve_config(
            directory="$JAILRUN_UNDEFINED_TEST_VAR_42/proj/sub"
        )
        self.assertNotIn("BAD", result.get("sandbox_passthrough_env", []))


if __name__ == "__main__":
    unittest.main()
