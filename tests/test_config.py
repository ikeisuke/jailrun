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

    def test_codex_contract(self):
        # v0.5.0 Unit 001: codex entry was *not* touched (registry.npmjs.org
        # was promoted to COMMON instead). Pin the exact set to detect
        # accidental over- or under-permission in this entry.
        self.assertEqual(
            set(config.BUILTIN_PROXY_DOMAINS["codex"]),
            {"chatgpt.com", "ab.chatgpt.com", "api.openai.com"},
        )

    def test_kiro_cli_contract(self):
        # v0.5.0 Unit 001: kiro-cli entry was not touched. Pin the exact set
        # so any unintended addition / removal is caught by tests.
        self.assertEqual(
            set(config.BUILTIN_PROXY_DOMAINS["kiro-cli"]),
            {
                "*.kiro.dev",
                "q.us-east-1.amazonaws.com",
                "q.eu-central-1.amazonaws.com",
                "desktop-release.q.us-east-1.amazonaws.com",
                "cognito-identity.us-east-1.amazonaws.com",
                "oidc.ap-northeast-1.amazonaws.com",
                "*.awsapps.com",
                "client-telemetry.us-east-1.amazonaws.com",
            },
        )

    def test_kiro_covers_iam_identity_center_start_url(self):
        # Kiro organization login asks for an IAM Identity Center start URL
        # such as https://<directory-id>.awsapps.com/start.
        self.assertIn("*.awsapps.com",
                      config.BUILTIN_PROXY_DOMAINS["kiro-cli"])

    def test_kiro_awsapps_wildcard_matches_subdomains_only(self):
        # Pin the contract between BUILTIN_PROXY_DOMAINS["kiro-cli"] (data
        # layer) and proxy.match_domain (interpretation layer). A change on
        # either side that breaks subdomain-only matching must be detected.
        import proxy

        allowed = set(config.BUILTIN_PROXY_DOMAINS["kiro-cli"])

        # Subdomains (including IAM Identity Center directory hosts) match.
        self.assertTrue(proxy.match_domain("d-1234567890.awsapps.com", allowed))
        self.assertTrue(proxy.match_domain("deep.sub.awsapps.com", allowed))

        # Base domain itself does not match (existing *.example.com semantics).
        self.assertFalse(proxy.match_domain("awsapps.com", allowed))

        # Label-boundary and suffix-extension attack hosts do not match.
        self.assertFalse(proxy.match_domain("awsappsXXX.com", allowed))
        self.assertFalse(
            proxy.match_domain("evil.awsapps.com.attacker.example", allowed)
        )

    def test_common_contract(self):
        # COMMON contract (values, not comments). Updated v0.5.0 Unit 001:
        # registry.npmjs.org was promoted from per-agent into COMMON because
        # node-project operations are needed across every agent.
        self.assertEqual(
            set(config.BUILTIN_PROXY_DOMAINS_COMMON),
            {
                "github.com",
                "api.github.com",
                "raw.githubusercontent.com",
                "registry.npmjs.org",
            },
        )

    def test_claude_contract(self):
        # v0.5.0 Unit 001 / Issue #99: claude entry final set. Pinning the
        # full set guards against unintended over-permission as well as the
        # documented additions (parity with codex / kiro-cli contract tests).
        self.assertEqual(
            set(config.BUILTIN_PROXY_DOMAINS["claude"]),
            {
                "api.anthropic.com",
                "statsig.anthropic.com",
                "platform.claude.com",
                "downloads.claude.ai",
                "chatgpt.com",
                "ab.chatgpt.com",
                "api.openai.com",
            },
        )

    def test_common_has_no_duplicates(self):
        # COMMON list must remain duplicate-free; merger relies on this.
        self.assertEqual(
            len(config.BUILTIN_PROXY_DOMAINS_COMMON),
            len(set(config.BUILTIN_PROXY_DOMAINS_COMMON)),
        )

    def test_opt_in_structure_pin(self):
        # Unit 006 / Issue #101: pin the full opt-in registry so any drift in
        # the per-agent telemetry endpoint set is caught by tests.
        self.assertEqual(
            config.BUILTIN_PROXY_DOMAINS_OPT_IN,
            {
                "claude": ["http-intake.logs.us5.datadoghq.com"],
                "gemini": ["www.google-analytics.com"],
            },
        )

    def test_opt_in_disjoint_from_non_opt_in(self):
        # Unit 006 structural invariant: the opt-in registry must never share
        # any domain with the non-opt-in registries. A future telemetry domain
        # accidentally added to BUILTIN_PROXY_DOMAINS (or vice versa) must
        # fail this assertion.
        non_opt_in: set[str] = set(config.BUILTIN_PROXY_DOMAINS_COMMON)
        for domains in config.BUILTIN_PROXY_DOMAINS.values():
            non_opt_in.update(domains)
        opt_in: set[str] = set()
        for domains in config.BUILTIN_PROXY_DOMAINS_OPT_IN.values():
            opt_in.update(domains)
        intersection = non_opt_in & opt_in
        self.assertEqual(
            intersection, set(),
            f"opt-in and non-opt-in registries must not overlap; "
            f"found duplicates: {sorted(intersection)}",
        )

    def test_kiro_cli_awsapps_not_in_opt_in(self):
        # Unit 002 added "*.awsapps.com" to the kiro-cli non-opt-in entry for
        # IAM Identity Center auth. Guard against accidental migration into
        # the opt-in registry during refactors.
        opt_in_kiro = config.BUILTIN_PROXY_DOMAINS_OPT_IN.get("kiro-cli", [])
        self.assertNotIn("*.awsapps.com", opt_in_kiro)
        self.assertIn("*.awsapps.com", config.BUILTIN_PROXY_DOMAINS["kiro-cli"])


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

    # ------------------------------------------------------------------
    # Unit 006 / Issue #101: opt-in telemetry merge contract.
    # ------------------------------------------------------------------

    def test_opt_in_default_excluded(self):
        # With proxy enabled but opt_in_telemetry omitted (default False),
        # telemetry endpoints must not appear in the effective allowlist.
        self._write('[global]\nproxy_enabled = true\n')
        result = config.resolve_config(app="claude")
        merged = result.get("proxy_allow_domains", [])
        self.assertNotIn("http-intake.logs.us5.datadoghq.com", merged)
        # Explicit False behaves identically.
        result2 = config.resolve_config(app="claude", opt_in_telemetry=False)
        self.assertNotIn(
            "http-intake.logs.us5.datadoghq.com",
            result2.get("proxy_allow_domains", []),
        )

    def test_opt_in_telemetry_enabled_includes(self):
        # opt_in_telemetry=True must add the agent's opt-in domains AND keep
        # the existing non-opt-in domains.
        self._write('[global]\nproxy_enabled = true\n')
        result = config.resolve_config(app="claude", opt_in_telemetry=True)
        merged = result.get("proxy_allow_domains", [])
        self.assertIn("http-intake.logs.us5.datadoghq.com", merged)
        self.assertIn("api.anthropic.com", merged)

    def test_opt_in_does_not_affect_non_opt_in(self):
        # Toggling opt_in_telemetry must only add opt-in domains; the
        # non-opt-in slice (COMMON + per-agent non-opt-in) must stay invariant.
        self._write('[global]\nproxy_enabled = true\n')
        result_off = config.resolve_config(app="claude")
        result_on = config.resolve_config(app="claude", opt_in_telemetry=True)
        non_opt_in_set = set(config.BUILTIN_PROXY_DOMAINS_COMMON) | set(
            config.BUILTIN_PROXY_DOMAINS["claude"]
        )
        merged_off = set(result_off.get("proxy_allow_domains", []))
        merged_on = set(result_on.get("proxy_allow_domains", []))
        self.assertEqual(merged_off, non_opt_in_set)
        expected_on = non_opt_in_set | set(
            config.BUILTIN_PROXY_DOMAINS_OPT_IN["claude"]
        )
        self.assertEqual(merged_on, expected_on)
        # Non-opt-in portion is unchanged between off and on.
        self.assertEqual(
            merged_on - set(config.BUILTIN_PROXY_DOMAINS_OPT_IN["claude"]),
            merged_off,
        )

    def test_opt_in_telemetry_proxy_disabled_does_not_merge(self):
        # proxy_enabled=False short-circuits the whole builtin merge, including
        # the opt-in branch. Even with opt_in_telemetry=True, the user list
        # must remain untouched.
        self._write(
            '[global]\n'
            'proxy_enabled = false\n'
            'proxy_allow_domains = ["only.example.com"]\n'
        )
        result = config.resolve_config(app="claude", opt_in_telemetry=True)
        self.assertEqual(
            result.get("proxy_allow_domains"),
            ["only.example.com"],
        )

    def test_opt_in_telemetry_for_agent_without_opt_in_noop(self):
        # codex / kiro-cli do not appear in BUILTIN_PROXY_DOMAINS_OPT_IN. With
        # opt_in_telemetry=True the effective allowlist is identical to off.
        self._write('[global]\nproxy_enabled = true\n')
        for app in ("codex", "kiro-cli"):
            with self.subTest(app=app):
                off = set(
                    config.resolve_config(app=app).get(
                        "proxy_allow_domains", []
                    )
                )
                on = set(
                    config.resolve_config(
                        app=app, opt_in_telemetry=True
                    ).get("proxy_allow_domains", [])
                )
                self.assertEqual(off, on)

    def test_opt_in_telemetry_keyword_only(self):
        # opt_in_telemetry must be keyword-only: a positional True after
        # (app, directory) must raise TypeError rather than silently enable
        # telemetry merging.
        self._write('[global]\nproxy_enabled = true\n')
        with self.assertRaises(TypeError):
            config.resolve_config("claude", "", True)  # noqa: ASYM

    def test_opt_in_telemetry_non_true_values_do_not_enable(self):
        # The opt-in branch uses `is True` (not truthy check) so that a
        # non-bool truthy value (e.g. string "false", int 1, list [True])
        # cannot silently enable telemetry merging. Defensive: keeps the
        # policy flag fail-safe under caller mistakes.
        self._write('[global]\nproxy_enabled = true\n')
        for sneaky in ("false", "True", 1, [True], object()):
            with self.subTest(value=sneaky):
                result = config.resolve_config(
                    app="claude", opt_in_telemetry=sneaky
                )
                self.assertNotIn(
                    "http-intake.logs.us5.datadoghq.com",
                    result.get("proxy_allow_domains", []),
                )


class SandboxSecretInjectKeyTests(unittest.TestCase):
    """Unit 001 (#108): sandbox_secret_inject list-type config key.

    Verifies the declaration layer only: the key is registered as a
    list-type default and round-trips through to_shell() as the uppercase
    SANDBOX_SECRET_INJECT envelope key. Semantic validation / injection is
    out of scope (Unit 002)."""

    def test_default_is_empty_list(self):
        self.assertIn("sandbox_secret_inject", config.DEFAULTS)
        self.assertEqual(config.DEFAULTS["sandbox_secret_inject"], [])

    def test_registered_as_list_key(self):
        self.assertIn("sandbox_secret_inject", config.LIST_KEYS)

    def test_present_in_known_keys(self):
        self.assertIn("sandbox_secret_inject", config.KNOWN_KEYS)

    def test_to_shell_uppercases_and_joins(self):
        out = config.to_shell(
            {"sandbox_secret_inject": ["OPENAI_API_KEY:default", "ANTHROPIC_API_KEY:work"]}
        )
        self.assertIn(
            "SANDBOX_SECRET_INJECT=OPENAI_API_KEY:default ANTHROPIC_API_KEY:work",
            out,
        )

    def test_to_shell_empty_list_yields_empty_value(self):
        out = config.to_shell({"sandbox_secret_inject": []})
        self.assertIn("SANDBOX_SECRET_INJECT=", out)


if __name__ == "__main__":
    unittest.main()
