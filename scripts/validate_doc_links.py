#!/usr/bin/env python3
"""Validate relative markdown links across plugin skill docs.

Catches dead `references/foo.md` and `../examples/bar.sh` links inside
plugins/*/skills/*/ that would otherwise rot silently as the doc tree
evolves. Anchor fragments (`#section-id`) are stripped before file
existence checks; we don't validate that the anchor resolves on
GitHub's renderer (that would require a full markdown slugger).

What this checks:
  - Every Markdown link of the form `[text](relative/path.md)` resolves
    to an existing file or directory under the repo.
  - Includes Markdown link references inside any *.md file under
    plugins/*/skills/*/.
  - Excludes absolute URLs (http://, https://, mailto:) — those are
    out of scope for this checker (link rot in external services
    isn't a CI-actionable failure).
  - Excludes pure-anchor links (`(#some-section)`) — same-file anchors
    aren't checked here.

Exit code:
  0  — all links resolve
  1  — at least one link is dead

Run: python3 scripts/validate_doc_links.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")


def is_external_or_anchor(target: str) -> bool:
    """Skip http(s) URLs, mailto, in-page anchors, and protocol-relative."""
    if target.startswith(("http://", "https://", "mailto:", "//", "tel:")):
        return True
    if target.startswith("#"):
        return True
    return False


def strip_fragment(target: str) -> str:
    """Drop `#anchor` from a relative link — file-existence check only cares about path."""
    if "#" in target:
        return target.split("#", 1)[0]
    return target


def collect_doc_files() -> list[Path]:
    docs: list[Path] = []
    for plugin_dir in (ROOT / "plugins").glob("*/skills/*"):
        if not plugin_dir.is_dir():
            continue
        docs.extend(plugin_dir.rglob("*.md"))
    return sorted(docs)


def validate_file(md: Path) -> list[tuple[int, str, str]]:
    """Return a list of (line_number, link_target, reason) for broken links."""
    broken: list[tuple[int, str, str]] = []
    text = md.read_text(encoding="utf-8")
    # Track line numbers via cumulative chars
    line_starts = [0]
    for i, ch in enumerate(text):
        if ch == "\n":
            line_starts.append(i + 1)

    def line_for(pos: int) -> int:
        # Binary search would be faster but the docs are small.
        for i in range(len(line_starts) - 1, -1, -1):
            if line_starts[i] <= pos:
                return i + 1
        return 1

    for m in LINK_RE.finditer(text):
        target = m.group(1).strip()
        if is_external_or_anchor(target):
            continue
        rel = strip_fragment(target)
        if not rel:
            # Pure-fragment after stripping (`(#anchor)`) — skipped already
            continue
        # Resolve relative to the markdown file's directory
        resolved = (md.parent / rel).resolve()
        if not resolved.exists():
            broken.append((line_for(m.start()), target, "no such file or directory"))
            continue
        # Trailing-slash links should resolve to a directory; without slash
        # we accept either file or directory (links to `references/` or
        # `references/recipes/` are common for "browse the folder").
        if rel.endswith("/") and not resolved.is_dir():
            broken.append((line_for(m.start()), target, "expected a directory (link ends with /)"))
    return broken


def main() -> int:
    docs = collect_doc_files()
    if not docs:
        print("ERROR: no plugin skill docs found under plugins/*/skills/*/", file=sys.stderr)
        return 1

    total_links_seen = 0
    all_broken: list[tuple[Path, int, str, str]] = []

    for md in docs:
        broken = validate_file(md)
        text = md.read_text(encoding="utf-8")
        # Count what we considered (for reporting; doesn't affect pass/fail)
        for m in LINK_RE.finditer(text):
            target = m.group(1).strip()
            if not is_external_or_anchor(target):
                total_links_seen += 1
        for line, target, reason in broken:
            all_broken.append((md, line, target, reason))

    if all_broken:
        for md, line, target, reason in all_broken:
            try:
                rel_md = md.relative_to(ROOT)
            except ValueError:
                rel_md = md
            print(f"FAIL  {rel_md}:{line}  ({target})  — {reason}", file=sys.stderr)
        print(
            f"\n{len(all_broken)} broken link(s) across {len(docs)} doc file(s); "
            f"{total_links_seen} relative link(s) checked total.",
            file=sys.stderr,
        )
        return 1

    print(
        f"OK    {total_links_seen} relative link(s) across {len(docs)} doc file(s) "
        f"all resolve."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
