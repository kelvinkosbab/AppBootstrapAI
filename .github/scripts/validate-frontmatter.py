#!/usr/bin/env python3
"""
Validate YAML frontmatter on every .claude/rules/*.md and
.claude/skills/*/SKILL.md, plus verify that any references/<name>.md
mentioned in a SKILL.md body actually exists on disk.

Catches the silent-bad mode where a rule loads with no scope (missing
globs:, or a paths: list that drifted from it — Claude Code scopes rules by
paths: only, so a rule without it loads in every session), or a skill claims to load reference docs that were renamed/
deleted without updating the SKILL.md.

Exits 1 with a list of problems if anything fails; exits 0 otherwise.

Run locally:    python3 .github/scripts/validate-frontmatter.py
Run in CI:      same — no dependencies beyond stdlib.
"""

from __future__ import annotations

import glob
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
RULES_DIR = REPO_ROOT / ".claude" / "rules"
SKILLS_DIR = REPO_ROOT / ".claude" / "skills"

REQUIRED_RULE_KEYS = ("description", "globs", "paths")
REQUIRED_SKILL_KEYS = ("name", "description", "license")


def split_frontmatter(text: str) -> str | None:
    """Return the YAML frontmatter body, or None if absent / malformed."""
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end < 0:
        # Frontmatter started but never closed.
        return None
    return text[4:end]


def has_key(frontmatter: str, key: str) -> bool:
    return bool(re.search(rf"^{re.escape(key)}\s*:", frontmatter, re.MULTILINE))


def split_top_level_commas(value: str) -> list[str]:
    """Split a globs string on commas outside {...} groups."""
    parts, current, depth = [], "", 0
    for char in value:
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(current)
            current = ""
            continue
        current += char
    if current:
        parts.append(current)
    return parts


def paths_match_globs(frontmatter: str) -> bool:
    """paths: (Claude Code) must list exactly the globs: (Cursor/Kiro) patterns."""
    globs = re.search(r'^globs:\s*"(.*)"\s*$', frontmatter, re.MULTILINE)
    block = re.search(r"^paths:\s*\n((?:\s+-\s+.*\n?)+)", frontmatter, re.MULTILINE)
    if not globs or not block:
        return False
    paths = re.findall(r'^\s+-\s+"(.*)"\s*$', block.group(1), re.MULTILINE)
    return paths == split_top_level_commas(globs.group(1))


def main() -> int:
    errors: list[str] = []
    rule_count = 0
    skill_count = 0

    # --- Rules ---
    for path_str in sorted(glob.glob(str(RULES_DIR / "*.md"))):
        path = Path(path_str)
        rule_count += 1
        text = path.read_text(encoding="utf-8")
        fm = split_frontmatter(text)
        if fm is None:
            errors.append(f"{path.relative_to(REPO_ROOT)}: missing or unterminated YAML frontmatter")
            continue
        for key in REQUIRED_RULE_KEYS:
            if not has_key(fm, key):
                errors.append(f"{path.relative_to(REPO_ROOT)}: frontmatter missing required key '{key}:'")
        if has_key(fm, "globs") and has_key(fm, "paths") and not paths_match_globs(fm):
            errors.append(
                f"{path.relative_to(REPO_ROOT)}: 'paths:' must be a quoted YAML list "
                f"of the comma-separated 'globs:' patterns, in order"
            )

    # --- Skills ---
    for path_str in sorted(glob.glob(str(SKILLS_DIR / "*" / "SKILL.md"))):
        path = Path(path_str)
        skill_count += 1
        text = path.read_text(encoding="utf-8")
        fm = split_frontmatter(text)
        if fm is None:
            errors.append(f"{path.relative_to(REPO_ROOT)}: missing or unterminated YAML frontmatter")
            continue
        for key in REQUIRED_SKILL_KEYS:
            if not has_key(fm, key):
                errors.append(f"{path.relative_to(REPO_ROOT)}: frontmatter missing required key '{key}:'")

        # Verify any references/<name>.md mentioned in the SKILL body exists.
        skill_dir = path.parent
        for ref_name in set(re.findall(r"references/([\w./-]+\.md)", text)):
            ref_path = skill_dir / "references" / ref_name
            if not ref_path.exists():
                errors.append(
                    f"{path.relative_to(REPO_ROOT)}: references 'references/{ref_name}' "
                    f"but it does not exist at {ref_path.relative_to(REPO_ROOT)}"
                )

    # Every rule and skill an audit topic names must exist.
    topics = json.loads((REPO_ROOT / "lib" / "topics.json").read_text(encoding="utf-8"))
    for name, spec in topics.items():
        if name.startswith("_"):
            continue
        for rule in (r for rs in spec["rules"].values() for r in rs):
            if not (RULES_DIR / rule).is_file():
                errors.append(f"lib/topics.json: topic '{name}' names missing rule '{rule}'")
        for skill in (s for ss in spec["skills"].values() for s in ss):
            if not (SKILLS_DIR / skill / "SKILL.md").is_file():
                errors.append(f"lib/topics.json: topic '{name}' names missing skill '{skill}'")

    # --- Report ---
    if errors:
        print("Frontmatter validation errors:")
        for err in errors:
            print(f"  - {err}")
        return 1

    print(f"OK: {rule_count} rules and {skill_count} skills validated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
