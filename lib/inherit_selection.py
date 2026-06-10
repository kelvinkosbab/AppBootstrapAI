#!/usr/bin/env python3
"""Read selection fields from a v1 or v2 manifest.

Called from install.sh's --upgrade flow to default unset CLI flags
(`--platform`, `--apple-language`, `--features`, `--agents`) to whatever the
target was last installed with. Output is pipe-separated for easy `IFS='|'
read` consumption on the bash side.

Args:
    sys.argv[1] — absolute path to the target's manifest.json.

Output (stdout, single line):
    platform|apple_language|features_input|agents_input|apple_platforms_input

Empty fields are emitted as empty strings; the bash caller decides whether
to use them based on which CLI flags the user passed. (apple_platforms_input
is absent in manifests written before the --apple-platforms selector — it just
comes back empty, and the bash side falls back to its default.)

Exit codes:
    0 — manifest read successfully (even if fields are empty)
    1 — file missing, unreadable, or not JSON
"""
import json
import sys


def main() -> int:
    try:
        with open(sys.argv[1]) as f:
            manifest = json.load(f)
    except (OSError, json.JSONDecodeError):
        return 1
    selection = manifest.get("selection", {})
    print(
        f"{selection.get('platform', '')}"
        f"|{selection.get('apple_language', '')}"
        f"|{selection.get('features_input', '')}"
        f"|{selection.get('agents_input', '')}"
        f"|{selection.get('apple_platforms_input', '')}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
