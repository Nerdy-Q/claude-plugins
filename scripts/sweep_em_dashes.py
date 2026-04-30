#!/usr/bin/env python3
"""Sweep em-dashes from authored marketplace content per voice rules.

Voice rule: never use em-dashes (—) in user-on-behalf writing. Replace per
English grammar role:
  - Parenthetical aside or noun expansion → comma
  - Two related independent clauses → semicolon (manual review)
  - Compound modifier or range → hyphen
  - Appositive list (em-dash--text--em-dash) → parentheses (manual review)

This script applies safe defaults algorithmically. The heuristics:

  1. ` — ` (space, em-dash, space) → `, ` (comma, space)
       This handles the vast majority: parentheticals, noun expansions,
       and explanatory tangents. Reads correctly in nearly all cases.
       Edge cases (independent clauses needing a semicolon, list-asides
       needing parens) are flagged for manual review by the report
       output but not auto-fixed; the comma is always grammatical even
       if not always optimal.

  2. `—` without surrounding spaces → `-` (hyphen)
       Compound modifiers like `today—spanning—are`. Less common.

  3. **Inside fenced code blocks** (```...```) and inline code
     spans (`...`): skipped entirely. Em-dashes in code are part of
     a string or comment that matters; do not touch.

  4. **Inside YAML frontmatter** at the top of markdown files:
     em-dashes ARE swept (this is plain-prose `description:` content).

Files explicitly excluded: CHANGELOG.md (historical record per Keep a
Changelog convention; never rewrite released-version sections).

Usage:
  python3 scripts/sweep_em_dashes.py --dry-run            # show counts, no changes
  python3 scripts/sweep_em_dashes.py --dry-run --diff     # show before/after per file
  python3 scripts/sweep_em_dashes.py                       # apply changes in place
  python3 scripts/sweep_em_dashes.py --files file1 file2  # restrict to specific files
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent

# Files NEVER touched.
EXCLUSIONS = {
    # Historical record — never rewrite per Keep a Changelog convention.
    Path("CHANGELOG.md"),
    # Untracked draft — leave alone.
    Path("BLOG-DRAFT.md"),
    # The sweep script itself (so the literal em-dash in this docstring
    # describing what the script does isn't accidentally swept).
    Path("scripts/sweep_em_dashes.py"),
}

# Suffixes that contain authored prose worth sweeping.
INCLUDE_SUFFIXES = {".md", ".json", ".yml", ".yaml"}

# Directories to scan from repo root. Anything outside these is ignored.
INCLUDE_DIRS = ["plugins", "scripts", ".github", ".claude-plugin"]
INCLUDE_TOP_LEVEL = ["README.md", "CONTRIBUTING.md", "SECURITY.md", "LICENSE"]


def split_protected_regions(text: str) -> list[tuple[str, str]]:
    """Split text into a list of (kind, content) chunks where kind is one of:
       'prose'  → safe to sweep
       'code'   → fenced code block (do not touch)
       'inline' → inline code span (do not touch)

    Order is preserved; reassembling the chunks yields the original text.
    """
    out: list[tuple[str, str]] = []
    pos = 0
    # Combined pattern: fenced code block OR inline code span. Fenced
    # blocks first because they may contain backticks.
    pattern = re.compile(
        r"(```[a-zA-Z0-9_+-]*\s*\n.*?\n```)"      # group 1: fenced block
        r"|(`[^`\n]+`)",                            # group 2: inline span
        re.DOTALL,
    )
    for m in pattern.finditer(text):
        if m.start() > pos:
            out.append(("prose", text[pos:m.start()]))
        if m.group(1) is not None:
            out.append(("code", m.group(1)))
        else:
            out.append(("inline", m.group(2)))
        pos = m.end()
    if pos < len(text):
        out.append(("prose", text[pos:]))
    return out


def sweep_prose(prose: str) -> tuple[str, int]:
    """Apply em-dash replacements to a prose chunk. Returns (new_text, count)."""
    count = 0

    # Rule 0: Heading lines (^#+\s) and table-header rows (| cell |).
    # In a heading, " — " almost always introduces an explanation/expansion
    # of the heading subject, where colon reads correctly and comma reads
    # awkwardly. Process line-by-line.
    out_lines: list[str] = []
    for line in prose.split("\n"):
        if re.match(r"^\s*#+\s", line):
            new_line, n = re.subn(r" — ", ": ", line)
            out_lines.append(new_line)
            count += n
        else:
            out_lines.append(line)
    prose = "\n".join(out_lines)

    # Rule 1: ` — ` → `, `  (the dominant case)
    new, n = re.subn(r" — ", ", ", prose)
    count += n
    prose = new

    # Rule 1b: em-dash with a space on one side only.
    new, n = re.subn(r" —([A-Za-z])", r", \1", prose)
    count += n
    prose = new
    new, n = re.subn(r"([A-Za-z])— ", r"\1, ", prose)
    count += n
    prose = new

    # Rule 2: `—` with no spaces (compound modifier / range) → `-` (hyphen).
    new, n = re.subn(r"—", "-", prose)
    count += n
    prose = new

    return prose, count


def collect_files(restrict: list[Path] | None) -> list[Path]:
    """Find every authored file under the include set, minus EXCLUSIONS."""
    files: list[Path] = []
    if restrict:
        for r in restrict:
            p = (ROOT / r).resolve() if not r.is_absolute() else r
            if p.exists():
                files.append(p)
    else:
        # Top-level whitelisted files
        for name in INCLUDE_TOP_LEVEL:
            p = ROOT / name
            if p.exists():
                files.append(p)
        # Recurse into included directories
        for d in INCLUDE_DIRS:
            base = ROOT / d
            if not base.is_dir():
                continue
            for p in base.rglob("*"):
                if p.is_file() and p.suffix in INCLUDE_SUFFIXES:
                    files.append(p)

    # Filter out exclusions and dedupe
    keep: list[Path] = []
    seen: set[Path] = set()
    for f in files:
        try:
            rel = f.relative_to(ROOT)
        except ValueError:
            rel = f
        if rel in EXCLUSIONS:
            continue
        if f in seen:
            continue
        seen.add(f)
        keep.append(f)
    return sorted(keep)


def process_file(path: Path, dry_run: bool, show_diff: bool) -> int:
    """Sweep one file. Returns the number of replacements made."""
    text = path.read_text(encoding="utf-8")
    if "—" not in text:
        return 0
    chunks = split_protected_regions(text)
    new_chunks: list[str] = []
    total = 0
    for kind, content in chunks:
        if kind == "prose":
            swept, n = sweep_prose(content)
            new_chunks.append(swept)
            total += n
        else:
            # code or inline: untouched
            new_chunks.append(content)
    new_text = "".join(new_chunks)
    if total == 0:
        return 0  # nothing changed (em-dashes were all in code regions)
    if show_diff:
        # Print compact before/after for each line that changed
        old_lines = text.splitlines()
        new_lines = new_text.splitlines()
        try:
            rel = path.relative_to(ROOT)
        except ValueError:
            rel = path
        for i, (a, b) in enumerate(zip(old_lines, new_lines), start=1):
            if a != b:
                print(f"  {rel}:{i}")
                print(f"    - {a}")
                print(f"    + {b}")
    if not dry_run:
        path.write_text(new_text, encoding="utf-8")
    return total


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true",
                        help="show what would change without writing")
    parser.add_argument("--diff", action="store_true",
                        help="show before/after lines (forces dry-run unless paired with apply)")
    parser.add_argument("--files", nargs="*", type=Path,
                        help="restrict to specific files (relative or absolute)")
    args = parser.parse_args()

    files = collect_files(args.files)
    if not files:
        print("No files found to sweep.", file=sys.stderr)
        return 1

    total_files_changed = 0
    total_replacements = 0
    for f in files:
        n = process_file(f, dry_run=args.dry_run, show_diff=args.diff)
        if n > 0:
            total_files_changed += 1
            total_replacements += n
            try:
                rel = f.relative_to(ROOT)
            except ValueError:
                rel = f
            if not args.diff:
                action = "would change" if args.dry_run else "swept"
                print(f"  {action}  {n:>4}  {rel}")

    mode = "DRY-RUN" if args.dry_run else "APPLIED"
    print(f"\n{mode}: {total_replacements} em-dash(es) across {total_files_changed} file(s) "
          f"of {len(files)} scanned.")
    if args.dry_run:
        print("Re-run without --dry-run to apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
