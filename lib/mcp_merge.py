#!/usr/bin/env python3
"""Merge a set of MCP recipes into the target's .claude/settings.local.json.

Called from install.sh's --with-mcps install path. The merge is idempotent
(existing entries with the same name are never overwritten) and computes a
stable sha256 of each added recipe's config so a future --upgrade can do
3-way diffs against the recipe shipped in the bundle.

Args:
    sys.argv[1] — absolute path to the target's settings.local.json (may
                  not yet exist; this script creates it).
    sys.argv[2] — absolute path to the mcp-recipes/ directory in the bundle.
    sys.argv[3] — space-separated list of MCP recipe names to install.

Output (stdout, machine-parseable):
    ADDED:name1=hash1,name2=hash2
    SKIPPED:name1,name2
    ---SETUP---
    NAME:<display name>
    HOMEPAGE:<url>          (optional)
    STEP:<step text>
    STEP:<step text>
    ... (one ---SETUP--- block per added recipe with setup notes)

Exit codes:
    0 — success
    2 — settings.local.json is not valid JSON (printed to stderr)
"""
import hashlib
import json
import os
import sys


def config_hash(config) -> str:
    """Stable sha256 of an MCP recipe's config blob.

    sort_keys + compact separators ensure that reformatting the recipe JSON
    file doesn't drift the hash — only semantic changes matter.
    """
    payload = json.dumps(config, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()


def main() -> int:
    settings_path = sys.argv[1]
    recipes_dir = sys.argv[2]
    mcp_names = sys.argv[3].split()

    # Load existing settings.local.json or start fresh.
    if os.path.exists(settings_path):
        with open(settings_path) as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError as e:
                print(
                    f"ERROR:{settings_path} is not valid JSON: {e}",
                    file=sys.stderr,
                )
                return 2
    else:
        data = {}

    mcps = data.setdefault("mcpServers", {})
    added = []        # list of (name, config_sha256)
    skipped = []
    setup_notes = []  # list of (display_name, [step, ...], homepage)

    for name in mcp_names:
        recipe_path = os.path.join(recipes_dir, f"{name}.json")
        with open(recipe_path) as f:
            recipe = json.load(f)
        entry_key = recipe["name"]
        if entry_key in mcps:
            skipped.append(entry_key)
            continue
        mcps[entry_key] = recipe["config"]
        added.append((entry_key, config_hash(recipe["config"])))
        if recipe.get("setup"):
            setup_notes.append((
                recipe.get("display_name", entry_key),
                recipe["setup"],
                recipe.get("homepage", ""),
            ))

    os.makedirs(os.path.dirname(settings_path), exist_ok=True)
    with open(settings_path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

    # Emit machine-parseable result lines for bash to capture.
    # ADDED line carries name=hash pairs separated by commas.
    print("ADDED:" + ",".join(f"{n}={h}" for n, h in added))
    print("SKIPPED:" + ",".join(skipped))
    for display, steps, homepage in setup_notes:
        print("---SETUP---")
        print(f"NAME:{display}")
        if homepage:
            print(f"HOMEPAGE:{homepage}")
        for step in steps:
            print(f"STEP:{step}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
