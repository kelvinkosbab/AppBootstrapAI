# Upgrading and removing

## Upgrading an existing install

Once a repo has run `install.sh`, the bundle keeps evolving — new rules ship, existing rules get tightened, skills gain references. The `--upgrade` flow lets you see what would change and apply it surgically, without ever touching files you've customized.

```bash
# 1. Plan — read-only preview. Inherits --platform / --apple-language / --features from the manifest.
/path/to/AppBootstrapAI/install.sh /your/repo --upgrade

# 2. Apply — execute the safe rows. Conflicts default to SKIP; orphans stay.
/path/to/AppBootstrapAI/install.sh /your/repo --upgrade --apply

# 3. Apply + opt into a new feature category (e.g., adopt Foundation Models support post-iOS-26).
/path/to/AppBootstrapAI/install.sh /your/repo --upgrade --features recommended,ai --apply

# 4. Preview apply without writing — combines --apply with --dry-run.
/path/to/AppBootstrapAI/install.sh /your/repo --upgrade --apply --dry-run

# 5. Aggressive: overwrite locally-edited files where the bundle also changed (loses local edits).
/path/to/AppBootstrapAI/install.sh /your/repo --upgrade --apply --force-conflicts

# 6. Aggressive: delete files retired upstream or no longer in --features.
/path/to/AppBootstrapAI/install.sh /your/repo --upgrade --apply --prune
```

The plan classifies every tracked file:

- **Up to date** — installed hash matches the bundle. No action.
- **Safe to update** — bundle has new content; you haven't touched the file locally. `--apply` overwrites.
- **Locally edited** — you modified the file after install; bundle unchanged. The upgrade always leaves these alone.
- **Conflict** — both local edits and upstream changes since install. Default is skip-with-warning; `--force-conflicts` overwrites.
- **Out of scope** — file was installed under one `--features` set but isn't part of the current selection. Manifest tracks it; `--prune` removes it.
- **Retired upstream** — bundle no longer ships this file. Listed but not auto-deleted; `--prune` removes it.
- **Would add** — new files in the bundle that fit your current `--features` and aren't in the manifest yet. `--apply` writes them.

The diff is **3-way per file**: installed hash (what we wrote at install), current disk hash (what's there now), and bundle hash (what the bundle ships today). That's how the plan can tell *"you've edited this"* apart from *"someone re-ran an installer."*

### Migrating from older manifests

Installs from before manifest schema v2 don't have content hashes recorded, so the diff has no baseline. The migration is a single command — no files are touched, only the manifest is rewritten:

```bash
/path/to/AppBootstrapAI/install.sh /your/repo --upgrade --apply --migrate-manifest
```

After migration, future `--upgrade` runs can do real 3-way diffs. Note: v1 `mcps_requested` is not carried over; re-add MCPs via `--with-mcps` if needed.

### MCP entries get the same 3-way diff

MCP recipes installed via `--with-mcps` are tracked in the manifest with their `config_sha256`. `--upgrade` runs the same per-entry classification on `.claude/settings.local.json`:

- **Up to date** — recipe config matches what's in `settings.local.json` and the manifest.
- **Safe to update** — recipe shipped a new config; you haven't touched the entry. `--apply` overwrites `mcpServers.<name>`.
- **Locally edited** — you customized the entry (changed args, added env vars). Always left alone.
- **Conflict** — both you AND the recipe diverged from the original. Default skip; `--force-conflicts` overwrites.
- **Orphan** — recipe no longer ships in the bundle, OR the entry vanished from `settings.local.json`. `--prune` drops the manifest record (and removes the `mcpServers.<name>` entry if it still exists).

The hash is computed over the recipe's `config` object with stable sort + compact separators, so reformatting `mcp-recipes/<name>.json` doesn't drift the hash.

### Renames

When the bundle renames a rule or skill upstream, the rename is tracked in [`RENAMES.md`](../RENAMES.md) at the bundle root. The upgrade plan folds the migration into a single rename row instead of "deleted X, added Y." Two forms:

- **Rule renames** (file-level): `apple-old.md → apple-new.md`. Resolves to `.claude/rules/<old>.md` → `.claude/rules/<new>.md`.
- **Skill renames** (directory-level): `swift-old-pro → swift-new-pro`. Resolves to a path-prefix rewrite of every file under the old skill dir.

Renames classify as **safe** (current matches installed or bundle — moving the file loses nothing) or **conflict** (you have uncommitted edits at the old path, OR the new path already exists from a user-authored file). Default skip on conflict; `--force-conflicts` applies anyway.

### Where the bundle changed: the GitHub compare URL

When the upgrade plan detects that the bundle's current `git rev-parse HEAD` differs from what the manifest recorded at install time, and the bundle's `origin` remote is a GitHub URL, the header prints a compare link:

```
  installed bundle commit: 6a1afb1461fb
  current bundle commit:   30ee587195be
  changes between them:    https://github.com/kelvinkosbab/AppBootstrapAI/compare/6a1afb14...30ee5871
```

Click through to see exactly what shipped between your install and now. Falls back gracefully when the bundle isn't a git checkout, has no GitHub remote, or both commits resolve to "unknown".

### Things the upgrade flow won't do

- **`CLAUDE.md`** is never auto-touched. The plan surfaces "template advanced upstream" when relevant; the diff is for you to apply by hand. `CLAUDE.md` fills with project-specific content fast, so auto-merge is dangerous.
- **`.claude/settings.json`** gets the same treatment for the same reason — you probably added permissions, tweaked allowlists. The plan informs; you merge.
- **Non-`mcpServers` keys in `settings.local.json`** are preserved across upgrade-apply. Only `mcpServers.<name>` entries listed in the manifest's `mcps_installed` get touched.
- **MCP additions** — `--upgrade` doesn't auto-add new MCP recipes. Adding an MCP is always explicit via `--with-mcps <name>`.

## Removing the install

```bash
# Default — delete every tracked file that hasn't been edited; keep CLAUDE.md / settings.json.
/path/to/AppBootstrapAI/install.sh /your/repo --uninstall

# Preview without writing
/path/to/AppBootstrapAI/install.sh /your/repo --uninstall --dry-run

# Aggressive: also delete locally-edited tracked files
/path/to/AppBootstrapAI/install.sh /your/repo --uninstall --force-conflicts

# Aggressive: also delete CLAUDE.md + settings.json
/path/to/AppBootstrapAI/install.sh /your/repo --uninstall --purge

# Leave settings.local.json MCP entries alone (don't touch your local MCP config)
/path/to/AppBootstrapAI/install.sh /your/repo --uninstall --keep-mcps
```

Classifications:

- **Will delete (unchanged since install)** — current hash matches what we wrote → safe to remove.
- **Locally edited — keep unless `--force-conflicts`** — current hash differs from installed hash. Skipping protects work you did.
- **User-protected — keep unless `--purge`** — `CLAUDE.md` and `.claude/settings.json` are always skipped by default (you almost certainly customized them).
- **MCP entries** — same 3-way safety: removed if `settings.local.json` matches the install-time hash, skipped otherwise unless `--force-conflicts`. Pass `--keep-mcps` to leave them all.

What `--uninstall` always does (regardless of flags):

- Removes the `# --- AppBootstrapAI (...) ---` block from `.gitignore`.
- Deletes the manifest at `.claude/.appbootstrap-manifest.json`.
- Cleans up empty parent directories under `.claude/` only — never touches your project root.
- Preserves every non-`mcpServers` key in `.claude/settings.local.json` (your permissions, custom fields, etc.).
