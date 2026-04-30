#!/usr/bin/env python3
"""Performance regression test for audit.py.

Real-world Power Pages portals have hundreds to low thousands of files.
A regression that introduces O(n²) scanning (e.g., for each web page,
re-walk every web template) would make audit times balloon from seconds
to minutes on large portals.

This test generates a synthetic portal with 1000 files spread across the
canonical structure and asserts audit completes within a generous budget.
The budget is intentionally loose — we're protecting against multi-minute
regressions, not measuring micro-performance.

What's generated:
  - 200 web pages (each with .webpage.yml + .webpage.copy.html)
  - 200 web templates (.webtemplate.source.html)
  - 200 content snippets (.contentsnippet.value.html)
  - 200 site settings (.sitesetting.yml)
  - 200 table permissions (.tablepermission.yml)

Run:
  python3 -m unittest plugins/pp-permissions-audit/skills/pp-permissions-audit/scripts/test_audit_performance.py
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
AUDIT_PY = SCRIPT_DIR / "audit.py"

# Generous budget. Real perf on a 1000-file portal is typically <1s on
# modern hardware; we set 15s as the regression alarm. CI runners may be
# slow — the budget is "much larger than expected" intentionally so that
# day-to-day variance doesn't flake the test, but a 10x regression does
# trip it.
BUDGET_SECONDS = 15.0

# How many of each entity type to generate
WEB_PAGES = 200
WEB_TEMPLATES = 200
CONTENT_SNIPPETS = 200
SITE_SETTINGS = 200
TABLE_PERMISSIONS = 200


class TestAuditPerformance(unittest.TestCase):
    """Audit must complete in linear time on a 1000-file portal."""

    @classmethod
    def setUpClass(cls):
        if not AUDIT_PY.is_file():
            raise unittest.SkipTest(f"audit.py not found at {AUDIT_PY}")
        cls.tmpdir = Path(tempfile.mkdtemp(prefix="pp-audit-perf-"))
        cls.site_dir = cls.tmpdir / "perf-test---perf-test"
        cls._build_fixture()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmpdir, ignore_errors=True)

    @classmethod
    def _build_fixture(cls):
        """Create a synthetic portal with N files of each type."""
        site = cls.site_dir
        site.mkdir(parents=True)
        (site / "website.yml").write_text(
            "adx_name: Performance Test\nadx_websitelanguage: 1033\n",
            encoding="utf-8",
        )

        # Web pages
        wp_dir = site / "web-pages"
        wp_dir.mkdir()
        for i in range(WEB_PAGES):
            page_dir = wp_dir / f"page-{i:03d}"
            page_dir.mkdir()
            (page_dir / f"page-{i:03d}.webpage.yml").write_text(
                f"adx_name: Page {i}\nadx_partialurl: page-{i}\n"
                f"adx_publishingstateid: Published\n",
                encoding="utf-8",
            )
            (page_dir / f"page-{i:03d}.webpage.copy.html").write_text(
                f"<h1>Page {i}</h1>\n", encoding="utf-8",
            )

        # Web templates
        wt_dir = site / "web-templates"
        wt_dir.mkdir()
        for i in range(WEB_TEMPLATES):
            template_dir = wt_dir / f"tmpl-{i:03d}"
            template_dir.mkdir()
            (template_dir / f"tmpl-{i:03d}.webtemplate.source.html").write_text(
                f"<div>Template {i}</div>\n", encoding="utf-8",
            )

        # Content snippets
        cs_dir = site / "content-snippets"
        cs_dir.mkdir()
        for i in range(CONTENT_SNIPPETS):
            snippet_dir = cs_dir / f"snippet-{i:03d}"
            snippet_dir.mkdir()
            (snippet_dir / f"snippet-{i:03d}.contentsnippet.value.html").write_text(
                f"snippet {i}", encoding="utf-8",
            )

        # Site settings
        ss_dir = site / "site-settings"
        ss_dir.mkdir()
        for i in range(SITE_SETTINGS):
            (ss_dir / f"setting-{i:03d}.sitesetting.yml").write_text(
                f"adx_name: TestSetting/{i}\nadx_value: value-{i}\n"
                f"statecode: 0\n",
                encoding="utf-8",
            )

        # Table permissions
        tp_dir = site / "table-permissions"
        tp_dir.mkdir()
        for i in range(TABLE_PERMISSIONS):
            (tp_dir / f"perm-{i:03d}.tablepermission.yml").write_text(
                f"adx_entityname: contact\n"
                f"adx_name: perm-{i}\n"
                f"adx_read: true\n"
                f"adx_create: false\n",
                encoding="utf-8",
            )

    def test_audit_completes_within_budget(self):
        """audit.py must finish a 1000-file portal under the regression budget."""
        start = time.monotonic()
        result = subprocess.run(
            [sys.executable, str(AUDIT_PY), str(self.site_dir), "--json"],
            capture_output=True, text=True, check=False,
            timeout=BUDGET_SECONDS + 5.0,  # absolute hard kill if WAY over
        )
        elapsed = time.monotonic() - start

        self.assertLess(
            elapsed, BUDGET_SECONDS,
            f"audit took {elapsed:.2f}s on a {self._fixture_file_count()}-file portal "
            f"(budget: {BUDGET_SECONDS}s). Likely a regression.",
        )
        # Quick sanity check that the run actually succeeded
        self.assertEqual(
            result.returncode, 0,
            f"audit exited non-zero on perf fixture: stderr={result.stderr!r}",
        )

    def test_audit_handles_large_portal_without_errors(self):
        """No tracebacks, no warnings on stderr that indicate failures."""
        result = subprocess.run(
            [sys.executable, str(AUDIT_PY), str(self.site_dir), "--json"],
            capture_output=True, text=True, check=False,
            timeout=BUDGET_SECONDS + 5.0,
        )
        # Stderr should not contain Python tracebacks
        self.assertNotIn(
            "Traceback (most recent call last)", result.stderr,
            f"audit raised an exception on perf fixture: {result.stderr}",
        )
        # Exit code 0 (or 1 with findings, but no other codes)
        self.assertIn(
            result.returncode, (0, 1),
            f"audit exit code {result.returncode} (expected 0 or 1)",
        )

    @classmethod
    def _fixture_file_count(cls) -> int:
        return sum(1 for _ in cls.site_dir.rglob("*") if _.is_file())


if __name__ == "__main__":
    unittest.main()
