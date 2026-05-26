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
- **Rule renames** — list the basename (must end in `.md`). Resolves to
  `.claude/rules/<old>.md` → `.claude/rules/<new>.md`. Example:
  `apple-foo.md → apple-bar.md`.
- **Skill renames** — list bare directory names (no `/`, no `.`). Resolves to
  a path-prefix rewrite: every file under `.claude/skills/<old>/` folds to
  `.claude/skills/<new>/<rest>` at classification time. Example:
  `swift-foo-pro → swift-bar-pro`.
- Lines starting with `#` are comments.
- Blank lines are ignored.
- Order matters only for chained renames (`a → b`, then later `b → c`).

## How upgrade uses this

For each pair `old → new`:

1. **Rule rename**: if the manifest has an entry for `.claude/rules/<old>.md`,
   the upgrade plan classifies it as a rename (not a delete+add). Under
   `--apply`, the bundle's new content is written at `.claude/rules/<new>.md`
   and the old file is deleted.
2. **Skill rename**: every manifest entry under `.claude/skills/<old>/` is
   prefix-rewritten to `.claude/skills/<new>/<rest>` at classification time.
   Under `--apply`, each file moves from old to new path; the manifest entry
   updates to the new skill name. The old skill's directory is left empty
   (and pruned by the empty-parent cleanup).
3. **Safety classification**: if `current_hash != installed_hash AND
   current_hash != bundle_hash` (user has uncommitted edits the rename would
   lose), the rename surfaces as a conflict — the user can pass
   `--force-conflicts` to apply anyway.
4. **Target collision**: if the new path already exists on disk and isn't
   itself in the manifest, the rename is also marked as a conflict (we never
   overwrite user-authored files at the new path).
5. If `old` is not in the manifest (was never installed for this user), the
   line is a no-op.

## Current renames

<!-- No renames yet. Add pairs above this line as the bundle evolves. -->
