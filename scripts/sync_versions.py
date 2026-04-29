#!/usr/bin/env python3
"""Sync live version references from versions.json into repo files.

This centralizes the version values that are meant to move forward over time:
- per-plugin manifest versions
- doc/template pins that should track a released repo tag

Historical changelog entries are intentionally excluded; they are archival.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
VERSIONS_PATH = ROOT / "versions.json"


def load_versions() -> dict:
    return json.loads(VERSIONS_PATH.read_text(encoding="utf-8"))


def dump_json(path: Path, data: dict) -> str:
    return json.dumps(data, indent=4, ensure_ascii=False) + "\n"


def replace_required(text: str, pattern: str, repl: str, path: Path) -> str:
    updated, count = re.subn(pattern, repl, text, flags=re.MULTILINE)
    if count == 0:
        raise ValueError(f"{path}: pattern not found: {pattern}")
    return updated


def sync_plugin_manifest(path: Path, expected_version: str) -> str:
    data = json.loads(path.read_text(encoding="utf-8"))
    data["version"] = expected_version
    return dump_json(path, data)


def sync_audit_ci_md(path: Path, ci_ref: str) -> str:
    text = path.read_text(encoding="utf-8")
    raw_url = (
        "https://raw.githubusercontent.com/Nerdy-Q/claude-power-pages-plugins/"
        f"{ci_ref}/plugins/pp-permissions-audit/skills/pp-permissions-audit/scripts/audit.py"
    )
    text = replace_required(
        text,
        r"pinned tag \(`v[0-9]+\.[0-9]+\.[0-9]+` by default\)",
        f"pinned tag (`{ci_ref}` by default)",
        path,
    )
    text = replace_required(
        text,
        r"The template uses `AUDIT_REF: 'v[0-9]+\.[0-9]+\.[0-9]+'`",
        f"The template uses `AUDIT_REF: '{ci_ref}'`",
        path,
    )
    text = re.sub(
        r"https://raw\.githubusercontent\.com/Nerdy-Q/claude-power-pages-plugins/"
        r"v[0-9]+\.[0-9]+\.[0-9]+/plugins/pp-permissions-audit/skills/pp-permissions-audit/scripts/audit\.py",
        raw_url,
        text,
    )
    return text


def sync_audit_github_action(path: Path, ci_ref: str) -> str:
    text = path.read_text(encoding="utf-8")
    text = replace_required(
        text,
        r"#   AUDIT_REF:\s+'v[0-9]+\.[0-9]+\.[0-9]+'\s+\(recommended for production projects\)",
        f"#   AUDIT_REF: '{ci_ref}'   (recommended for production projects)",
        path,
    )
    text = replace_required(
        text,
        r"AUDIT_REF:\s+'v[0-9]+\.[0-9]+\.[0-9]+'",
        f"AUDIT_REF:  '{ci_ref}'",
        path,
    )
    return text


def build_expected_files(versions: dict) -> dict[Path, str]:
    plugin_versions = versions["plugins"]
    ci_ref = versions["docs"]["pp_permissions_audit_ci_ref"]
    return {
        ROOT / "plugins/pp-portal/.claude-plugin/plugin.json": sync_plugin_manifest(
            ROOT / "plugins/pp-portal/.claude-plugin/plugin.json",
            plugin_versions["pp-portal"],
        ),
        ROOT / "plugins/pp-sync/.claude-plugin/plugin.json": sync_plugin_manifest(
            ROOT / "plugins/pp-sync/.claude-plugin/plugin.json",
            plugin_versions["pp-sync"],
        ),
        ROOT / "plugins/pp-permissions-audit/.claude-plugin/plugin.json": sync_plugin_manifest(
            ROOT / "plugins/pp-permissions-audit/.claude-plugin/plugin.json",
            plugin_versions["pp-permissions-audit"],
        ),
        ROOT / "plugins/pp-permissions-audit/CI.md": sync_audit_ci_md(
            ROOT / "plugins/pp-permissions-audit/CI.md",
            ci_ref,
        ),
        ROOT / "plugins/pp-permissions-audit/examples/github-actions/power-pages-audit.yml": sync_audit_github_action(
            ROOT / "plugins/pp-permissions-audit/examples/github-actions/power-pages-audit.yml",
            ci_ref,
        ),
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if tracked versioned files are out of sync with versions.json",
    )
    args = parser.parse_args(argv)

    versions = load_versions()
    expected_files = build_expected_files(versions)
    drifted: list[Path] = []

    for path, expected in expected_files.items():
        current = path.read_text(encoding="utf-8")
        if current != expected:
            drifted.append(path)
            if not args.check:
                path.write_text(expected, encoding="utf-8")
                print(f"UPDATED {path.relative_to(ROOT)}")
        elif not args.check:
            print(f"OK      {path.relative_to(ROOT)}")

    if args.check and drifted:
        print("Version drift detected:", file=sys.stderr)
        for path in drifted:
            print(f" - {path.relative_to(ROOT)}", file=sys.stderr)
        print(
            "Run `python3 scripts/sync_versions.py` and commit the resulting changes.",
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
