"""Unit tests for lib/write_manifest.py.

Run with: python3 -m unittest discover -s tests
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib", "write_manifest.py")


def write(stdin, **kwargs):
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "manifest.json")
        args = [sys.executable, SCRIPT, out]
        for k, v in kwargs.items():
            args += [f"--{k.replace('_', '-')}", v]
        subprocess.run(args, input=stdin, text=True, check=True)
        with open(out, encoding="utf-8") as f:
            text = f.read()
    return text, json.loads(text)


class WriteManifestTests(unittest.TestCase):
    def test_quotes_and_backslashes_stay_valid(self):
        path = 'C:\\Users\\me\\"odd" bundle'
        repo = 'https://example.com/a"b\\c.git'
        _, m = write("F|.claude/rules/a\"b.md|rule|core|abc|\n", bundle_path=path, bundle_repo=repo)
        self.assertEqual(m["bundle"], {"path": path, "repo": repo})
        self.assertEqual(m["files"][0]["path"], '.claude/rules/a"b.md')

    def test_entries_and_selection(self):
        text, m = write(
            "F|.claude/rules/x.md|rule|core|h1|\n"
            "F|.gitignore|gitignore-block|-||\n"
            "F|.claude/skills/s/SKILL.md|skill-file|testing|h2|s\n"
            "M|xcodebuildmcp|cfg\n"
            "M|other|\n",
            platform="apple", features_resolved="core testing", agents_resolved="",
        )
        self.assertEqual(m["schema_version"], 2)
        self.assertEqual(m["selection"]["platform"], "apple")
        self.assertEqual(m["selection"]["features_resolved"], ["core", "testing"])
        self.assertEqual(m["selection"]["agents_resolved"], [])
        self.assertIsNone(m["files"][1]["sha256"])
        self.assertNotIn("skill", m["files"][0])
        self.assertEqual(m["files"][2]["skill"], "s")
        self.assertEqual(m["mcps_installed"], [
            {"name": "xcodebuildmcp", "config_sha256": "cfg"},
            {"name": "other", "config_sha256": None},
        ])
        # One line per file entry, so the manifest stays diffable and greppable.
        self.assertIn('    {"path": ".claude/rules/x.md", "type": "rule"', text)

    def test_empty_lists(self):
        _, m = write("")
        self.assertEqual(m["files"], [])
        self.assertEqual(m["mcps_installed"], [])


if __name__ == "__main__":
    unittest.main()
