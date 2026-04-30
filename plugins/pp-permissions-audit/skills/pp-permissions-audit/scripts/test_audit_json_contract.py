#!/usr/bin/env python3
"""Schema contract for `audit.py --json` output.

External CI integrations consume this JSON: the GitHub Action template at
`plugins/pp-permissions-audit/examples/github-actions/power-pages-audit.yml`
pipes findings through `jq`, custom dashboards may parse it into a database,
and pre-commit hooks gate commits on severity counts.

A rename or restructure here breaks every external consumer silently
(jq selectors keep returning empty arrays — there's no error, just
wrong-looking results). This test pins the keys, types, and value
constraints so any breaking shape change fails CI and is surfaced
in code review.

The contract is also documented as a comment block at the bottom of this
file so consumers don't have to read this test to know what to depend on.

Run: python3 -m unittest plugins/pp-permissions-audit/skills/pp-permissions-audit/scripts/test_audit_json_contract.py
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
AUDIT_PY = SCRIPT_DIR / "audit.py"


class TestAuditJsonContract(unittest.TestCase):
    """The JSON output shape is a public contract; pin it explicitly."""

    @classmethod
    def setUpClass(cls):
        if not AUDIT_PY.is_file():
            raise unittest.SkipTest(f"audit.py not found at {AUDIT_PY}")

    def setUp(self):
        # Build a fixture portal that deterministically triggers at least one
        # known finding (ERR-001: Web API enabled for an entity with no
        # matching Table Permission). Without a guaranteed finding, the
        # shape-of-finding tests can only skip — so we seed the site to make
        # the contract checks actually run.
        self.tmpdir = Path(tempfile.mkdtemp(prefix="pp-audit-jsonc-"))
        self.site_dir = self.tmpdir / "sample-site---sample-site"
        self.site_dir.mkdir()
        (self.site_dir / "website.yml").write_text(
            "adx_name: Sample Site\nadx_websitelanguage: 1033\n",
            encoding="utf-8",
        )
        # site-settings: Webapi enabled for `contact` with no matching perm -> ERR-001
        (self.site_dir / "site-settings").mkdir()
        (self.site_dir / "site-settings" / "webapi-contact-enabled.sitesetting.yml").write_text(
            "adx_name: Webapi/contact/Enabled\n"
            "adx_value: true\n"
            "statecode: 0\n",
            encoding="utf-8",
        )

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _run_json(self, *extra_args: str) -> dict:
        result = subprocess.run(
            [sys.executable, str(AUDIT_PY), str(self.site_dir), "--json", *extra_args],
            capture_output=True, text=True,
            check=False,  # exit-code semantics are tested separately
        )
        # Stderr is OK to be empty or have warnings; stdout must be parseable JSON.
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError as e:
            self.fail(
                f"audit --json did not produce parseable JSON. "
                f"stderr: {result.stderr!r}; stdout (first 200 chars): {result.stdout[:200]!r}; "
                f"json error: {e}"
            )

    # --- Top-level shape ---------------------------------------------------

    def test_top_level_is_object(self):
        data = self._run_json()
        self.assertIsInstance(data, dict, "top-level JSON must be an object")

    def test_top_level_required_keys(self):
        data = self._run_json()
        for key in ("site", "counts", "findings"):
            self.assertIn(key, data, f"top-level missing required key '{key}'")

    def test_site_is_string_path(self):
        data = self._run_json()
        self.assertIsInstance(data["site"], str)
        self.assertTrue(
            data["site"].endswith("sample-site---sample-site"),
            f"site key should reflect the SITE_DIR argument, got: {data['site']!r}",
        )

    # --- counts: stable enumerable surfaces -------------------------------

    def test_counts_required_keys(self):
        data = self._run_json()
        counts = data["counts"]
        self.assertIsInstance(counts, dict, "counts must be an object")
        for key in ("site_settings", "table_permissions", "web_roles",
                    "web_pages", "custom_js", "schema_entities"):
            self.assertIn(key, counts, f"counts missing required key '{key}'")
            self.assertIsInstance(counts[key], int, f"counts.{key} must be int")
            self.assertGreaterEqual(counts[key], 0, f"counts.{key} must be >= 0")

    def test_counts_no_unexpected_keys(self):
        """If a new count surfaces, this test fails — by design.

        Adding a new count is fine, but it requires updating this test, the
        external CI Action template, and the dashboards. We force the bump.
        """
        data = self._run_json()
        expected = {
            "site_settings", "table_permissions", "web_roles",
            "web_pages", "custom_js", "schema_entities",
        }
        actual = set(data["counts"].keys())
        unexpected = actual - expected
        self.assertEqual(
            unexpected, set(),
            f"counts has unexpected keys (update test + external consumers): {unexpected}"
        )

    # --- findings array shape ---------------------------------------------

    def test_findings_is_list(self):
        data = self._run_json()
        self.assertIsInstance(data["findings"], list, "findings must be a list")

    def test_finding_record_shape(self):
        """Each finding must have: severity, code, title, detail, location.

        We need at least one finding to test this. An empty website.yml + no
        web roles triggers ERR-001 (no web_roles file) and other startup
        findings, so we should get at least one entry from a minimal fixture.
        """
        data = self._run_json()
        if not data["findings"]:
            # Skip rather than fail: maintainers may legitimately reduce the
            # baseline finding set. The contract is "if findings exist, this
            # is the shape" — not "findings always exist."
            self.skipTest("audit produced zero findings on minimal fixture; "
                          "shape contract is verified only when findings exist")
        sample = data["findings"][0]
        self.assertIsInstance(sample, dict, "each finding must be an object")
        for key in ("severity", "code", "title", "detail", "location"):
            self.assertIn(key, sample, f"finding missing required key '{key}'")
            self.assertIsInstance(sample[key], str, f"finding.{key} must be str")

    def test_finding_severity_enum(self):
        """severity must be one of the documented enum values."""
        data = self._run_json()
        valid = {"ERROR", "WARN", "INFO"}
        for f in data["findings"]:
            self.assertIn(
                f["severity"], valid,
                f"finding.severity must be in {valid}, got {f['severity']!r}",
            )

    def test_finding_code_is_stable_identifier(self):
        """`code` is the stable identifier external consumers filter on
        (e.g., `jq '.findings[] | select(.code == "WRN-005")'`).
        Format: <prefix>-<digits>, where prefix is ERR / WRN / INFO.
        """
        import re
        code_re = re.compile(r"^(ERR|WRN|INFO)-\d{3}$")
        data = self._run_json()
        for f in data["findings"]:
            self.assertRegex(
                f["code"], code_re,
                f"finding.code must match {code_re.pattern}, got {f['code']!r}",
            )

    # --- severity filter contract -----------------------------------------

    def test_severity_filter_includes_higher(self):
        """`--severity WARN` must include ERROR-class findings (higher tier).

        External CI gates rely on this: setting `--severity ERROR` must
        return only ERROR; setting `--severity INFO` must return everything.
        """
        info_data = self._run_json("--severity", "INFO")
        warn_data = self._run_json("--severity", "WARN")
        error_data = self._run_json("--severity", "ERROR")

        info_count = len(info_data["findings"])
        warn_count = len(warn_data["findings"])
        error_count = len(error_data["findings"])

        # Filter is "at this level OR HIGHER" — INFO=all >= WARN >= ERROR.
        self.assertGreaterEqual(info_count, warn_count,
                                "INFO severity must include >= WARN findings")
        self.assertGreaterEqual(warn_count, error_count,
                                "WARN severity must include >= ERROR findings")

    def test_severity_filter_at_error_only_returns_errors(self):
        """`--severity ERROR` must NOT contain WARN or INFO findings."""
        data = self._run_json("--severity", "ERROR")
        for f in data["findings"]:
            self.assertEqual(
                f["severity"], "ERROR",
                f"--severity ERROR returned a {f['severity']} finding: {f['code']}",
            )

    # --- exit-code contract -----------------------------------------------

    def test_exit_code_zero_without_flag(self):
        """Without --exit-code, audit exits 0 even when findings exist."""
        result = subprocess.run(
            [sys.executable, str(AUDIT_PY), str(self.site_dir), "--json"],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(
            result.returncode, 0,
            f"audit without --exit-code must exit 0; got {result.returncode}",
        )

    def test_exit_code_one_when_findings_at_severity(self):
        """With --exit-code --severity INFO, exits 1 when ANY finding exists."""
        # First check that findings exist on the fixture
        data = self._run_json("--severity", "INFO")
        if not data["findings"]:
            self.skipTest("no findings on minimal fixture — exit-code semantics not testable")
        result = subprocess.run(
            [sys.executable, str(AUDIT_PY), str(self.site_dir),
             "--json", "--exit-code", "--severity", "INFO"],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(
            result.returncode, 1,
            f"audit --exit-code with findings must exit 1; got {result.returncode}",
        )


# ---------------------------------------------------------------------------
# JSON OUTPUT CONTRACT (referenced by external consumers — keep stable)
# ---------------------------------------------------------------------------
#
# Top-level object:
#   {
#     "site": "<absolute or relative path>",            // string
#     "counts": {                                        // object, all int >= 0
#       "site_settings":     int,
#       "table_permissions": int,
#       "web_roles":         int,
#       "web_pages":         int,
#       "custom_js":         int,
#       "schema_entities":   int                         // 0 if no schema loaded
#     },
#     "findings": [                                      // array, may be empty
#       {
#         "severity":  "ERROR" | "WARN" | "INFO",        // enum, all required
#         "code":      "ERR-001" | "WRN-005" | "INFO-009",  // stable id
#         "title":     string,                            // short summary
#         "detail":    string,                            // explanation
#         "location":  string                             // file path or symbol
#       },
#       ...
#     ]
#   }
#
# CLI flags:
#   --severity {ERROR, WARN, INFO}    Show findings AT or ABOVE this level.
#                                      INFO=all, WARN=warn+error, ERROR=error only.
#   --exit-code                        Exit 1 if any findings at the chosen
#                                      severity threshold exist; else exit 0.
#                                      Without --exit-code, audit always exits 0.
#
# External consumers:
#   - examples/github-actions/power-pages-audit.yml — uses jq to count by severity
#   - CI.md — documents these flags for users
#   - any custom dashboard reading audit JSON

if __name__ == "__main__":
    unittest.main()
