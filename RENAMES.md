# RENAMES.md — bundle file renames across versions

This file is read by `./install.sh --upgrade` so that file renames in the bundle
are recognized as renames (not as a delete + add pair). When a rule or skill
gets renamed in the AppBootstrapAI bundle, add a line here.

## Format

```
old-name.md → new-name.md
old-skill   → new-skill
```

- One pair per line, separated by a Unicode `→` (U+2192) or the ASCII `->`.
- Rule filenames are listed as the basename under `.claude/rules/` (e.g.
  `apple-foo.md`).
- Skill names are the directory name under `.claude/skills/` (e.g. `swift-foo-pro`).
- Lines starting with `#` are comments.
- Blank lines are ignored.
- Order matters only for chained renames (`a → b`, then later `b → c`).

## How upgrade uses this

For each pair `old → new`:

1. If the manifest at the user's target has an entry for `old` and the bundle
   no longer contains `old`, the upgrade flow folds the delete+add into a single
   "renamed: old → new" row.
2. If the user has a local edit on `old`, the rename surfaces as a conflict —
   the user can `--force-conflicts` to write `new` with the bundle's current
   content (and `--prune` to remove `old`).
3. If `old` is not in the manifest (was never installed for this user), the
   line is a no-op.

## Current renames

<!-- No renames yet. Add pairs above this line as the bundle evolves. -->
