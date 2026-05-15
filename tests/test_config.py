#!/usr/bin/env python3
"""Unit tests for lib/config.py: BUILTIN_PROXY_DOMAINS merge contract.

Cycle v0.4.0 / Unit 003 / Issue #85.

Verifies that resolve_config() correctly merges BUILTIN_PROXY_DOMAINS_COMMON
+ BUILTIN_PROXY_DOMAINS[<app>] + the user's proxy_allow_domains, with the
gemini agent newly added in this unit."""

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# Match the import pattern used by tests/test_config_cli.py: insert lib/ on
# sys.path and import the module by its bare name (`config`), so we test the
# module boundary rather than the file path.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

import config  # noqa: E402


class BuiltinProxyDomainsTests(unittest.TestCase):
    """Static contract: the builtin domain dictionaries themselves."""

    def test_gemini_entry_present(self):
        self.assertIn("gemini", config.BUILTIN_PROXY_DOMAINS,
                     "BUILTIN_PROXY_DOMAINS must include a 'gemini' key")

    def test_gemini_covers_auth_category(self):
        # Intent M3 minimum: at least one Google OAuth / account auth domain.
        gemini = config.BUILTIN_PROXY_DOMAINS["gemini"]
        auth_candidates = {"accounts.google.com", "oauth2.googleapis.com"}
        self.assertTrue(
            auth_candidates & set(gemini),
            f"gemini entry must include at least one of {auth_candidates}; "
            f"got {gemini}",
        )

    def test_gemini_covers_api_category(self):
        # Intent M3 minimum: at least one Gemini API endpoint.
        gemini = config.BUILTIN_PROXY_DOMAINS["gemini"]
        api_candidates = {
            "generativelanguage.googleapis.com",
            "cloudcode-pa.googleapis.com",
        }
        self.assertTrue(
            api_candidates & set(gemini),
            f"gemini entry must include at least one of {api_candidates}; "
            f"got {gemini}",
        )

    def test_existing_agents_not_regressed(self):
        # Regression guard: Unit 003 must not drop any pre-existing entries.
        for app in ("claude", "codex", "kiro-cli"):
            self.assertIn(app, config.BUILTIN_PROXY_DOMAINS)
            self.assertGreater(len(config.BUILTIN_PROXY_DOMAINS[app]), 0,
                               f"{app} entry must remain non-empty")

    def test_common_unchanged_set(self):
        # COMMON list (values, not comments) must remain the GitHub trio.
        self.assertEqual(
            set(config.BUILTIN_PROXY_DOMAINS_COMMON),
            {"github.com", "api.github.com", "raw.githubusercontent.com"},
        )


class ResolveConfigMergeTests(unittest.TestCase):
    """Merge contract: resolve_config() output for proxy_allow_domains."""

    def setUp(self):
        # Point config.config_file at a fresh tmpdir for each test so we are
        # never sensitive to the caller's real ~/.config/jailrun/config.toml.
        self._tmp = tempfile.TemporaryDirectory()
        self._path = Path(self._tmp.name) / "config.toml"
        self._patch = patch.object(config, "config_file",
                                   return_value=self._path)
        self._patch.start()

    def tearDown(self):
        self._patch.stop()
        self._tmp.cleanup()

    def _write(self, body: str) -> None:
        self._path.write_text(body)

    def test_gemini_app_merges_common_plus_gemini(self):
        # No user-supplied proxy_allow_domains; merger should fill in the
        # union of COMMON + the gemini agent entry.
        self._write('[global]\nproxy_enabled = true\n')
        result = config.resolve_config(app="gemini")
        merged = set(result.get("proxy_allow_domains", []))
        for d in config.BUILTIN_PROXY_DOMAINS_COMMON:
            self.assertIn(d, merged, f"COMMON domain {d} missing for gemini")
        for d in config.BUILTIN_PROXY_DOMAINS["gemini"]:
            self.assertIn(d, merged, f"gemini domain {d} missing")

    def test_existing_agents_still_get_their_domains(self):
        # Regression: claude / codex / kiro-cli must each still receive their
        # own builtin entries when proxy is enabled.
        self._write('[global]\nproxy_enabled = true\n')
        for app in ("claude", "codex", "kiro-cli"):
            with self.subTest(app=app):
                result = config.resolve_config(app=app)
                merged = set(result.get("proxy_allow_domains", []))
                for d in config.BUILTIN_PROXY_DOMAINS[app]:
                    self.assertIn(d, merged,
                                  f"{app} domain {d} missing after merge")

    def test_user_supplied_domains_deduped_against_builtins(self):
        # When the user already lists a builtin in their config, the merge
        # must not add it again (no duplicates in the resulting list).
        self._write(
            '[global]\n'
            'proxy_enabled = true\n'
            'proxy_allow_domains = ["github.com", "accounts.google.com",'
            ' " custom.example.com "]\n'
        )
        result = config.resolve_config(app="gemini")
        merged = result.get("proxy_allow_domains", [])
        # No duplicates anywhere in the list.
        self.assertEqual(len(merged), len(set(merged)),
                         f"duplicates in merged list: {merged}")
        # User entries preserved at the head.
        self.assertEqual(merged[0], "github.com")
        self.assertEqual(merged[1], "accounts.google.com")
        # gemini-only domains still appended.
        self.assertIn("generativelanguage.googleapis.com", merged)

    def test_proxy_disabled_does_not_merge_builtins(self):
        # When proxy_enabled is false the merger leaves user list untouched
        # (and builtins are not added).
        self._write(
            '[global]\n'
            'proxy_enabled = false\n'
            'proxy_allow_domains = ["only.example.com"]\n'
        )
        result = config.resolve_config(app="gemini")
        self.assertEqual(result.get("proxy_allow_domains"),
                         ["only.example.com"])
        # No builtin leaked in.
        self.assertNotIn("github.com", result.get("proxy_allow_domains", []))
        self.assertNotIn("accounts.google.com",
                         result.get("proxy_allow_domains", []))

    def test_unknown_app_only_gets_common(self):
        # An app key not listed in BUILTIN_PROXY_DOMAINS should still get the
        # COMMON entries (and only those, plus any user entries).
        self._write('[global]\nproxy_enabled = true\n')
        result = config.resolve_config(app="some-unknown-agent")
        merged = set(result.get("proxy_allow_domains", []))
        self.assertEqual(merged, set(config.BUILTIN_PROXY_DOMAINS_COMMON))


if __name__ == "__main__":
    unittest.main()
