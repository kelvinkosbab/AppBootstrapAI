#!/usr/bin/env python3
"""Write .claude/.appbootstrap-manifest.json (schema v2) for install.sh.

Scalars come in as --key value arguments. File and MCP entries come in on
stdin, one per line, '|'-separated:

    F|rel_path|type|category|sha256|skill_name
    M|name|config_sha256

An empty sha256 or skill becomes null or is left out, as before. Using json
here instead of printf keeps paths and URLs with quotes or backslashes valid.
"""

import argparse
import json
import sys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("output")
    for key in (
        "installed-at", "bundle-commit", "bundle-path", "bundle-repo",
        "platform", "apple-language",
        "apple-platforms-input", "apple-platforms-resolved",
        "android-platforms-input", "android-platforms-resolved",
        "features-input", "features-resolved",
        "agents-input", "agents-resolved",
    ):
        ap.add_argument(f"--{key}", default="")
    a = ap.parse_args()

    files, mcps = [], []
    for line in sys.stdin.read().splitlines():
        if not line:
            continue
        kind, _, rest = line.partition("|")
        if kind == "F":
            path, type_, cat, sha, skill = (rest.split("|") + [""] * 5)[:5]
            entry = {"path": path, "type": type_, "category": cat, "sha256": sha or None}
            if skill:
                entry["skill"] = skill
            files.append(entry)
        elif kind == "M":
            name, _, sha = rest.partition("|")
            mcps.append({"name": name, "config_sha256": sha or None})

    manifest = {
        "schema_version": 2,
        "installed_at": a.installed_at,
        "bundle_commit": a.bundle_commit,
        "bundle": {"path": a.bundle_path, "repo": a.bundle_repo},
        "selection": {
            "platform": a.platform,
            "apple_language": a.apple_language,
            "apple_platforms_input": a.apple_platforms_input,
            "apple_platforms_resolved": a.apple_platforms_resolved.split(),
            "android_platforms_input": a.android_platforms_input,
            "android_platforms_resolved": a.android_platforms_resolved.split(),
            "features_input": a.features_input,
            "features_resolved": a.features_resolved.split(),
            "agents_input": a.agents_input,
            "agents_resolved": a.agents_resolved.split(),
        },
        "files": files,
        "mcps_installed": mcps,
    }

    # One line per file and MCP entry keeps the manifest diffable and greppable.
    text = json.dumps({k: v for k, v in manifest.items() if k not in ("files", "mcps_installed")},
                      indent=2, ensure_ascii=False)
    def block(key, items):
        if not items:
            return f'  "{key}": []'
        body = ",\n".join("    " + json.dumps(i, ensure_ascii=False) for i in items)
        return f'  "{key}": [\n{body}\n  ]'
    text = text[:-2] + ",\n" + block("files", files) + ",\n" + block("mcps_installed", mcps) + "\n}\n"
    json.loads(text)  # never write a manifest we can't read back

    with open(a.output, "w", encoding="utf-8") as f:
        f.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
