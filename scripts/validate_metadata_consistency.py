#!/usr/bin/env python3
"""Validate that plugin marketplace metadata stays consistent with skill content.

What this catches:

  1. **Plugin description vs skill description drift** — each plugin's
     marketplace description (`plugins/<p>/.claude-plugin/plugin.json`) must
     share core topic keywords with its primary SKILL.md frontmatter
     description. If the description is updated in one place and not the
     other, the marketplace listing and the skill matcher disagree about
     what the plugin does.

  2. **Keywords without coverage** — every keyword listed in plugin.json
     should appear (verbatim or as a normalized form) somewhere in either
     the plugin description, the SKILL.md description, or the SKILL.md body.
     A keyword that doesn't surface anywhere is dead metadata that won't
     help the skill matcher and creates confusion.

  3. **Plugin name consistency** — plugin.json `name` must match the
     containing folder, AND must match the SKILL.md frontmatter `name`
     for the primary skill (which itself must match the skill folder).

These checks complement the SKILL.md frontmatter validator already in CI
(which verifies frontmatter exists + name-matches-folder); this script
adds the cross-file consistency layer.

Run: python3 scripts/validate_metadata_consistency.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def normalize(token: str) -> str:
    """Normalize a keyword for fuzzy match: lowercase, strip whitespace,
    convert hyphens to spaces (so 'classic-portal' matches 'classic portal').
    """
    return token.lower().replace("-", " ").replace("_", " ").strip()


def keyword_appears_in(keyword: str, *texts: str) -> bool:
    """Return True if a normalized keyword appears in any of the given texts.

    Matches are word-boundary-aware to avoid false positives (e.g., 'pac'
    shouldn't match 'package'). Both hyphenated and space-separated forms
    are accepted.
    """
    norm = normalize(keyword)
    if not norm:
        return False
    # Build patterns: one for the hyphenated original, one for the
    # normalized space-separated form.
    patterns = {keyword, norm, keyword.replace("-", " "), keyword.replace("_", " ")}
    for pat in patterns:
        if not pat:
            continue
        # Word-boundary regex against case-insensitive haystacks
        regex = re.compile(r"\b" + re.escape(pat) + r"\b", re.IGNORECASE)
        for text in texts:
            if regex.search(text):
                return True
    return False


def read_plugin_metadata(plugin_dir: Path) -> dict:
    pj = plugin_dir / ".claude-plugin" / "plugin.json"
    if not pj.exists():
        return {}
    return json.loads(pj.read_text(encoding="utf-8"))


def read_skill_frontmatter(skill_md: Path) -> dict:
    """Parse the frontmatter block of a SKILL.md and return as a dict.
    Only handles simple `key: value` lines (sufficient for SKILL.md format).
    """
    text = skill_md.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not m:
        return {}
    fm: dict[str, str] = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip()
    return fm


def read_skill_body(skill_md: Path) -> str:
    text = skill_md.read_text(encoding="utf-8")
    # Strip the frontmatter block before checking body content
    return re.sub(r"^---\n.*?\n---\n", "", text, count=1, flags=re.DOTALL)


def primary_skill_for_plugin(plugin_dir: Path) -> Path | None:
    """Each plugin has a primary skill at plugins/<p>/skills/<p>/SKILL.md."""
    plugin_name = plugin_dir.name
    candidate = plugin_dir / "skills" / plugin_name / "SKILL.md"
    if candidate.exists():
        return candidate
    # Fallback: any SKILL.md under the plugin
    matches = list(plugin_dir.glob("skills/*/SKILL.md"))
    return matches[0] if matches else None


def main() -> int:
    plugins_dir = ROOT / "plugins"
    if not plugins_dir.is_dir():
        print(f"ERROR: plugins/ not found at {plugins_dir}", file=sys.stderr)
        return 1

    plugin_dirs = sorted(p for p in plugins_dir.iterdir() if p.is_dir())
    if not plugin_dirs:
        print("ERROR: no plugins found", file=sys.stderr)
        return 1

    all_ok = True
    total_keywords_checked = 0

    for plugin_dir in plugin_dirs:
        plugin_name = plugin_dir.name
        meta = read_plugin_metadata(plugin_dir)
        if not meta:
            print(f"FAIL  {plugin_name}: missing or invalid plugin.json", file=sys.stderr)
            all_ok = False
            continue

        # 1. Plugin name == folder name
        if meta.get("name") != plugin_name:
            print(f"FAIL  {plugin_name}: plugin.json name={meta.get('name')!r} != folder",
                  file=sys.stderr)
            all_ok = False

        # 2. Primary skill exists and its frontmatter name matches plugin name
        skill_md = primary_skill_for_plugin(plugin_dir)
        if not skill_md:
            print(f"FAIL  {plugin_name}: no primary SKILL.md", file=sys.stderr)
            all_ok = False
            continue
        skill_fm = read_skill_frontmatter(skill_md)
        if skill_fm.get("name") != plugin_name:
            print(f"FAIL  {plugin_name}: SKILL.md frontmatter name={skill_fm.get('name')!r} "
                  f"!= plugin name", file=sys.stderr)
            all_ok = False

        # 3. Description drift — both descriptions must share at least 3
        # significant lowercase content words
        plugin_desc = meta.get("description", "") or ""
        skill_desc = skill_fm.get("description", "") or ""
        if not plugin_desc or not skill_desc:
            print(f"FAIL  {plugin_name}: missing description in plugin.json or SKILL.md",
                  file=sys.stderr)
            all_ok = False
            continue

        # Tokenize on word boundaries, lowercase, drop short stop-words.
        STOP = {"the", "and", "for", "that", "with", "this", "use", "when",
                "are", "from", "into", "not", "but", "all", "your", "you",
                "any", "via", "out", "its", "their", "have", "has", "can",
                "may", "should", "will", "must", "would", "etc", "such"}
        def content_words(s: str) -> set[str]:
            words = re.findall(r"[a-zA-Z][a-zA-Z]{3,}", s.lower())
            return {w for w in words if w not in STOP}
        common = content_words(plugin_desc) & content_words(skill_desc)
        if len(common) < 3:
            print(f"FAIL  {plugin_name}: plugin.json and SKILL.md descriptions "
                  f"share only {len(common)} content words ({sorted(common)}); "
                  f"likely drift",
                  file=sys.stderr)
            all_ok = False

        # 4. Every keyword in plugin.json must appear in plugin description
        # OR skill description OR skill body
        skill_body = read_skill_body(skill_md)
        keywords = meta.get("keywords", [])
        for kw in keywords:
            total_keywords_checked += 1
            if not keyword_appears_in(kw, plugin_desc, skill_desc, skill_body):
                print(f"FAIL  {plugin_name}: keyword '{kw}' is in plugin.json but "
                      f"appears nowhere in plugin description, SKILL.md description, "
                      f"or SKILL.md body — dead metadata",
                      file=sys.stderr)
                all_ok = False

        if all_ok:
            print(f"OK    {plugin_name}: name match, description shares {len(common)} terms, "
                  f"all {len(keywords)} keywords have coverage")

    if all_ok:
        print(f"\nMetadata consistency: {len(plugin_dirs)} plugin(s), "
              f"{total_keywords_checked} keyword(s) checked, all consistent.")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
