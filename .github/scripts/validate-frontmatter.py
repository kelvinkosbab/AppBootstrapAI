#!/usr/bin/env python3
"""
Validate YAML frontmatter on every .claude/rules/*.md and
.claude/skills/*/SKILL.md, plus verify that any references/<name>.md
mentioned in a SKILL.md body actually exists on disk.

Also holds each rule to a size budget (RULE_MAX_BYTES, with a shrink-only
allowlist for rules not yet split into a checklist plus skill references).

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

REQUIRED_RULE_KEYS = ("description", "globs", "paths", "must")
# must: is copied into the always-loaded Gemini / Codex index, so it stays short.
MUST_ITEMS = (2, 5)
MUST_ITEM_CHARS = 160
MUST_RULE_CHARS = 600
REQUIRED_SKILL_KEYS = ("name", "description", "license")
# A rule loads into context whenever a matching file is open, so its size is
# a recurring cost. Long detail belongs in a skill's references/.
RULE_MAX_BYTES = 12 * 1024
# Rules not yet split, each capped at its size when the budget landed
# (rounded up to the next KB) so it can shrink but not grow.
# Remove an entry once the rule fits under RULE_MAX_BYTES.
OVERSIZED_RULES = {
    "apple-objc-accessibility-best-practices.md": 17 * 1024,
}


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


def must_errors(frontmatter: str) -> list[str]:
    """must: is a list of 2-5 short quoted strings with no inner quotes."""
    block = re.search(r"^must:\s*\n((?:  - .*\n?)+)", frontmatter, re.MULTILINE)
    if not block:
        return ["'must:' must be a YAML list of quoted strings"]
    lines = block.group(1).splitlines()
    items = [m.group(1) for line in lines if (m := re.fullmatch(r'  - "([^"\\]*)"', line))]
    errors = []
    if len(items) != len(lines):
        errors.append("'must:' items must be double-quoted with no inner quotes or backslashes")
    if not MUST_ITEMS[0] <= len(items) <= MUST_ITEMS[1]:
        errors.append(f"'must:' needs {MUST_ITEMS[0]}-{MUST_ITEMS[1]} items, has {len(items)}")
    if any(len(i) > MUST_ITEM_CHARS for i in items):
        errors.append(f"'must:' items must be at most {MUST_ITEM_CHARS} characters")
    if sum(len(i) for i in items) > MUST_RULE_CHARS:
        errors.append(f"'must:' totals more than {MUST_RULE_CHARS} characters")
    return errors


def size_errors(path: Path) -> list[str]:
    """Rules stay under RULE_MAX_BYTES; allowlisted ones never grow."""
    size = path.stat().st_size
    limit = OVERSIZED_RULES.get(path.name)
    if limit is None:
        if size > RULE_MAX_BYTES:
            return [
                (
                    f"{size} bytes is over the {RULE_MAX_BYTES}-byte rule budget; "
                    f"move detail into a skill's references/ and keep a checklist"
                )
            ]
        return []
    if size > limit:
        return [f"{size} bytes grew past its {limit}-byte allowance in OVERSIZED_RULES"]
    if size <= RULE_MAX_BYTES:
        return [f"now fits the {RULE_MAX_BYTES}-byte budget; remove it from OVERSIZED_RULES"]
    return []


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
        if has_key(fm, "must"):
            errors += [f"{path.relative_to(REPO_ROOT)}: {e}" for e in must_errors(fm)]
        errors += [f"{path.relative_to(REPO_ROOT)}: {e}" for e in size_errors(path)]

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

    for name in sorted(set(OVERSIZED_RULES) - {Path(p).name for p in glob.glob(str(RULES_DIR / "*.md"))}):
        errors.append(f"OVERSIZED_RULES names missing rule '{name}'")

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
