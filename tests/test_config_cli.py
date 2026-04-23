#!/usr/bin/env python3
"""Unit tests for lib/config_cli.py."""

import contextlib
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

import config  # noqa: E402
import config_cli  # noqa: E402


class ConfigCliTestBase(unittest.TestCase):
    """Base class: provides tmpdir + dual config_file patch."""

    def setUp(self):
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.config_path = Path(self._tmpdir.name) / "config.toml"

        p1 = patch("config_cli.config_file", return_value=self.config_path)
        p2 = patch("config.config_file", return_value=self.config_path)
        p1.start()
        self.addCleanup(p1.stop)
        p2.start()
        self.addCleanup(p2.stop)

    def write_fixture(self, toml_content: str) -> None:
        self.config_path.write_text(toml_content)

    def read_config_contents(self) -> str:
        return self.config_path.read_text()


class TestCmdLoad(ConfigCliTestBase):
    """cmd_load — stdout_only, defaults / app profile / dir longest-prefix."""

    def test_cl1_defaults_config_absent(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            config_cli.cmd_load([])
        output = buf.getvalue()
        self.assertIn('GH_TOKEN_NAME="classic"', output)
        self.assertIn('ALLOWED_AWS_PROFILES="default"', output)
        self.assertIn('DEFAULT_REGION="ap-northeast-1"', output)

    def test_cl2_app_profile_resolution(self):
        self.write_fixture(
            "[global]\n"
            'gh_token_name = "classic"\n'
            "\n"
            "[app.myapp]\n"
            'profile = "myprofile"\n'
            "\n"
            "[profile.myprofile]\n"
            'gh_token_name = "custom"\n'
        )
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            config_cli.cmd_load(["--app", "myapp"])
        output = buf.getvalue()
        self.assertIn('GH_TOKEN_NAME="custom"', output)

    def test_cl3_dir_longest_prefix_with_list_append(self):
        self.write_fixture(
            "[profile.base]\n"
            'sandbox_passthrough_env = ["BASE"]\n'
            "\n"
            '[dir."/tmp/proj"]\n'
            'sandbox_passthrough_env = ["SHORT"]\n'
            "\n"
            '[dir."/tmp/proj/sub"]\n'
            'profile = "base"\n'
            'sandbox_passthrough_env = ["X"]\n'
        )
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            config_cli.cmd_load(["--dir", "/tmp/proj/sub/nested"])
        output = buf.getvalue()
        self.assertIn('SANDBOX_PASSTHROUGH_ENV="BASE X"', output)
        self.assertNotIn("SHORT", output)


class TestCmdShow(ConfigCliTestBase):
    """cmd_show — stdout_only / SystemExit on missing config."""

    def test_cs1_prints_resolved_config(self):
        self.write_fixture(
            "[global]\n"
            'gh_token_name = "xxx"\n'
        )
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            config_cli.cmd_show([])
        output = buf.getvalue()
        self.assertIn('gh_token_name = "xxx"', output)
        self.assertIn("default_region", output)

    def test_cs2_exits_when_config_absent(self):
        err_buf = io.StringIO()
        with contextlib.redirect_stderr(err_buf):
            with self.assertRaises(SystemExit) as cm:
                config_cli.cmd_show([])
        self.assertEqual(cm.exception.code, 1)
        self.assertIn("no config file found", err_buf.getvalue())


class TestCmdSet(ConfigCliTestBase):
    """cmd_set — file_write, 5 error paths, --append no-op branch."""

    def _base_fixture(self) -> None:
        self.write_fixture(
            "[global]\n"
            'gh_token_name = "classic"\n'
            'allowed_aws_profiles = ["default"]\n'
        )

    def test_cset1_scalar_replace(self):
        self._base_fixture()
        config_cli.cmd_set(["gh_token_name", "fine-grained"])
        content = self.read_config_contents()
        self.assertIn('gh_token_name = "fine-grained"', content)

    def test_cset2_list_append(self):
        self._base_fixture()
        config_cli.cmd_set(["--append", "allowed_aws_profiles", "dev"])
        content = self.read_config_contents()
        self.assertIn('allowed_aws_profiles = ["default", "dev"]', content)

    def test_cset3_list_remove(self):
        self.write_fixture(
            "[global]\n"
            'allowed_aws_profiles = ["default", "dev"]\n'
        )
        config_cli.cmd_set(["--remove", "allowed_aws_profiles", "dev"])
        content = self.read_config_contents()
        self.assertIn('allowed_aws_profiles = ["default"]', content)
        self.assertNotIn('"dev"', content)

    def test_cset4_exits_when_config_absent(self):
        err_buf = io.StringIO()
        with contextlib.redirect_stderr(err_buf):
            with self.assertRaises(SystemExit) as cm:
                config_cli.cmd_set(["gh_token_name", "x"])
        self.assertEqual(cm.exception.code, 1)
        self.assertIn("no config file found", err_buf.getvalue())

    def test_cset5_exits_when_key_missing(self):
        self._base_fixture()
        err_buf = io.StringIO()
        with contextlib.redirect_stderr(err_buf):
            with self.assertRaises(SystemExit) as cm:
                config_cli.cmd_set([])
        self.assertEqual(cm.exception.code, 1)
        self.assertIn("missing KEY", err_buf.getvalue())

    def test_cset6_exits_when_unknown_key(self):
        self._base_fixture()
        err_buf = io.StringIO()
        with contextlib.redirect_stderr(err_buf):
            with self.assertRaises(SystemExit) as cm:
                config_cli.cmd_set(["unknown_key", "v"])
        self.assertEqual(cm.exception.code, 1)
        self.assertIn("unknown key", err_buf.getvalue())

    def test_cset7_exits_when_append_on_scalar(self):
        self._base_fixture()
        err_buf = io.StringIO()
        with contextlib.redirect_stderr(err_buf):
            with self.assertRaises(SystemExit) as cm:
                config_cli.cmd_set(["--append", "gh_token_name", "x"])
        self.assertEqual(cm.exception.code, 1)
        self.assertIn("--append is only supported for list-type keys", err_buf.getvalue())

    def test_cset8_exits_when_value_missing(self):
        self._base_fixture()
        err_buf = io.StringIO()
        with contextlib.redirect_stderr(err_buf):
            with self.assertRaises(SystemExit) as cm:
                config_cli.cmd_set(["gh_token_name"])
        self.assertEqual(cm.exception.code, 1)
        self.assertIn("missing VALUE", err_buf.getvalue())

    def test_cset9_append_duplicate_is_noop(self):
        self._base_fixture()
        err_buf = io.StringIO()
        with patch("config_cli.set_key_in_toml") as mock_set:
            with contextlib.redirect_stderr(err_buf):
                config_cli.cmd_set(["--append", "allowed_aws_profiles", "default"])
            mock_set.assert_not_called()
        self.assertIn("already in allowed_aws_profiles", err_buf.getvalue())
        content = self.read_config_contents()
        self.assertIn('allowed_aws_profiles = ["default"]', content)
        self.assertNotIn('"default", "default"', content)


class TestCmdEdit(ConfigCliTestBase):
    """cmd_edit — os.execvp mock, EDITOR env toggling."""

    def test_ce1_invokes_editor_from_env(self):
        self.write_fixture("[global]\n")
        with patch("config_cli.os.execvp") as mock_execvp, \
                patch.dict("os.environ", {"EDITOR": "vim"}):
            config_cli.cmd_edit([])
        mock_execvp.assert_called_once_with("vim", ["vim", str(self.config_path)])

    def test_ce2_defaults_to_vi_when_editor_unset(self):
        self.write_fixture("[global]\n")
        env_without_editor = {k: v for k, v in os.environ.items() if k != "EDITOR"}
        with patch("config_cli.os.execvp") as mock_execvp, \
                patch.dict("os.environ", env_without_editor, clear=True):
            config_cli.cmd_edit([])
        mock_execvp.assert_called_once_with("vi", ["vi", str(self.config_path)])

    def test_ce3_exits_and_skips_execvp_when_config_absent(self):
        with patch("config_cli.os.execvp") as mock_execvp:
            with self.assertRaises(SystemExit) as cm:
                config_cli.cmd_edit([])
        self.assertEqual(cm.exception.code, 1)
        mock_execvp.assert_not_called()


class TestCmdPath(ConfigCliTestBase):
    """cmd_path — stdout_only, prints patched config path."""

    def test_cp1_prints_config_path(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            config_cli.cmd_path([])
        self.assertIn(str(self.config_path), buf.getvalue())


class TestCmdInit(ConfigCliTestBase):
    """cmd_init — file_write, force / existing rejection."""

    def test_ci1_creates_new_config(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            config_cli.cmd_init([])
        self.assertTrue(self.config_path.exists())
        content = self.config_path.read_text()
        self.assertIn("[global]", content)
        self.assertIn("gh_token_name", content)
        self.assertIn("created:", buf.getvalue())

    def test_ci2_exits_when_existing_without_force(self):
        self.write_fixture("[global]\n")
        err_buf = io.StringIO()
        with contextlib.redirect_stderr(err_buf):
            with self.assertRaises(SystemExit) as cm:
                config_cli.cmd_init([])
        self.assertEqual(cm.exception.code, 1)
        self.assertIn("config already exists", err_buf.getvalue())

    def test_ci3_overwrites_with_force(self):
        self.write_fixture("[global]\ngh_token_name = \"old\"\n")
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            config_cli.cmd_init(["--force"])
        content = self.config_path.read_text()
        self.assertIn("[global]", content)
        self.assertIn("gh_token_name", content)
        self.assertIn("created:", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
