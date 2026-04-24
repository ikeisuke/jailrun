#!/usr/bin/env python3
"""Unit tests for lib/config_migrate.py."""

import contextlib
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

import config_migrate  # noqa: E402


LEGACY_MST1 = (
    'export GH_TOKEN_NAME="classic"\n'
    'ALLOWED_AWS_PROFILES="default dev"\n'
    'DEFAULT_AWS_PROFILE="work"\n'
    'SANDBOX_PASSTHROUGH_ENV="AWS_REGION HOME"\n'
)

EXPECTED_MST1_TOML = (
    "# jailrun config (migrated from shell format)\n"
    "# Docs: https://github.com/ikeisuke/jailrun\n"
    "\n"
    "[global]\n"
    'gh_token_name = "classic"\n'
    'allowed_aws_profiles = ["default", "dev"]\n'
    'default_aws_profile = "work"\n'
    'default_region = "ap-northeast-1"\n'
    "sandbox_deny_read_names = []\n"
    "sandbox_extra_deny_read = []\n"
    "sandbox_extra_allow_write = []\n"
    "sandbox_extra_allow_write_files = []\n"
    'sandbox_passthrough_env = ["AWS_REGION", "HOME"]\n'
    'proxy_enabled = "False"\n'
    "proxy_allow_domains = []\n"
    'keychain_profile = "allow"\n'
)

EXPECTED_CM1_TOML = EXPECTED_MST1_TOML + "\n"


class TestMigrateShellToToml(unittest.TestCase):
    """migrate_shell_to_toml — pure function, no patch needed."""

    def setUp(self):
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.legacy_path = Path(self._tmpdir.name) / "config"

    def write_legacy(self, content: str) -> None:
        self.legacy_path.write_text(content)

    def test_mst1_full_roundtrip_equal(self):
        self.write_legacy(LEGACY_MST1)
        result = config_migrate.migrate_shell_to_toml(self.legacy_path)
        self.assertEqual(result, EXPECTED_MST1_TOML)

    def test_mst2_github_prefix_stripped(self):
        self.write_legacy('GH_KEYCHAIN_SERVICE="github:token-name"\n')
        result = config_migrate.migrate_shell_to_toml(self.legacy_path)
        self.assertIn('gh_token_name = "token-name"', result)
        self.assertNotIn("github:", result)

    def test_mst3_gh_token_name_precedence(self):
        self.write_legacy(
            'GH_TOKEN_NAME="new-name"\n'
            'GH_KEYCHAIN_SERVICE="github:legacy-name"\n'
        )
        result = config_migrate.migrate_shell_to_toml(self.legacy_path)
        self.assertIn('gh_token_name = "new-name"', result)
        self.assertNotIn("legacy-name", result)

    def test_mst4_unknown_key_skipped(self):
        self.write_legacy('UNKNOWN_KEY="x"\n')
        result = config_migrate.migrate_shell_to_toml(self.legacy_path)
        self.assertNotIn("UNKNOWN_KEY", result)
        self.assertNotIn("unknown_key", result)
        self.assertIn('gh_token_name = "classic"', result)

    def test_mst5_comment_and_empty_lines_skipped(self):
        self.write_legacy(
            "# header comment\n"
            "\n"
            "NOEQUALSLINE\n"
        )
        result = config_migrate.migrate_shell_to_toml(self.legacy_path)
        self.assertNotIn("header comment", result)
        self.assertNotIn("NOEQUALSLINE", result)
        self.assertIn('gh_token_name = "classic"', result)

    def test_mst6_empty_list_key(self):
        self.write_legacy('SANDBOX_PASSTHROUGH_ENV=""\n')
        result = config_migrate.migrate_shell_to_toml(self.legacy_path)
        self.assertIn("sandbox_passthrough_env = []", result)

    def test_mst7_empty_file_yields_defaults(self):
        self.write_legacy("")
        result = config_migrate.migrate_shell_to_toml(self.legacy_path)
        self.assertIn('gh_token_name = "classic"', result)
        self.assertIn('allowed_aws_profiles = ["default"]', result)
        self.assertIn('default_aws_profile = "default"', result)
        self.assertIn('default_region = "ap-northeast-1"', result)

    def test_mst8_missing_path_raises_file_not_found(self):
        nonexistent = Path("/nonexistent/shell-config-xyz-9f3a2b")
        with self.assertRaises(FileNotFoundError):
            config_migrate.migrate_shell_to_toml(nonexistent)


class TestCmdMigrate(unittest.TestCase):
    """cmd_migrate — patches legacy_config_file / config_file on config_migrate."""

    def setUp(self):
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.legacy_path = Path(self._tmpdir.name) / "config"
        self.toml_path = Path(self._tmpdir.name) / "config.toml"

        p1 = patch(
            "config_migrate.legacy_config_file",
            return_value=self.legacy_path,
        )
        p2 = patch(
            "config_migrate.config_file",
            return_value=self.toml_path,
        )
        p1.start()
        self.addCleanup(p1.stop)
        p2.start()
        self.addCleanup(p2.stop)

    def write_legacy(self, content: str) -> None:
        self.legacy_path.write_text(content)

    def write_toml(self, content: str) -> None:
        self.toml_path.write_text(content)

    def test_cm1_writes_expected_toml(self):
        self.write_legacy(LEGACY_MST1)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            config_migrate.cmd_migrate([])
        self.assertTrue(self.toml_path.exists())
        self.assertEqual(self.toml_path.read_text(), EXPECTED_CM1_TOML)
        self.assertIn("migrated:", buf.getvalue())

    def test_cm2_exits_when_legacy_absent(self):
        err_buf = io.StringIO()
        with contextlib.redirect_stderr(err_buf):
            with self.assertRaises(SystemExit) as cm:
                config_migrate.cmd_migrate([])
        self.assertEqual(cm.exception.code, 1)
        self.assertIn("no legacy config found", err_buf.getvalue())

    def test_cm3_exits_when_toml_exists_without_force(self):
        self.write_legacy('GH_TOKEN_NAME="x"\n')
        self.write_toml("[global]\n# existing\n")
        err_buf = io.StringIO()
        with contextlib.redirect_stderr(err_buf):
            with self.assertRaises(SystemExit) as cm:
                config_migrate.cmd_migrate([])
        self.assertEqual(cm.exception.code, 1)
        self.assertIn("TOML config already exists", err_buf.getvalue())
        self.assertIn("# existing", self.toml_path.read_text())

    def test_cm4_force_overwrites_existing_toml(self):
        self.write_legacy('GH_TOKEN_NAME="new"\n')
        self.write_toml("[global]\n# OLD_MARKER\n")
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            config_migrate.cmd_migrate(["--force"])
        content = self.toml_path.read_text()
        self.assertNotIn("OLD_MARKER", content)
        self.assertIn("[global]", content)
        self.assertIn("gh_token_name", content)
        self.assertIn("migrated:", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
