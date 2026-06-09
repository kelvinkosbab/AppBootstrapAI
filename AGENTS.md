# AGENTS.md — operating AppBootstrapAI

> **For AI agents.** This file tells you how to *operate this package* —
> AppBootstrapAI — to set up / update / improve **another** repository. It is
> **not** the `AGENTS.md` that `install.sh --agents codex` writes into a target
> repo (that one carries the bundle's coding rules). Humans: see
> [README.md](README.md).

AppBootstrapAI is a drop-in bundle of AI agent steering — rules, skills (Claude),
and MCP recipes — copied into a target app repo by `install.sh`. It covers Apple
(Swift 6 / SwiftUI / visionOS / Testing / Core Data / Foundation Models) and
Android (Kotlin / Compose / Gradle / Hilt).

## Golden path — do this

```bash
# 1. Analyze the target. Read-only. Returns JSON with a ready-to-run command.
./install.sh recommend <dir> --json

# 2. Preview. Run the returned `preview_command` (= command + --dry-run). Writes nothing.
# 3. Apply.  Run the returned `command`. Then report what changed.
```

`recommend` introspects the directory and tells you exactly what to run — **one
call replaces grepping the tree yourself.** Trust its `command` / `preview_command`.

`recommend --json` returns:
`{ state, platform, apple_language, features, action, feature_reasons, command[], preview_command[], notes[] }`.

## Commands (verbs; each has a `--flag` alias, so old scripts keep working)

| Verb | Does | Alias |
|------|------|-------|
| `recommend [dir] [--json]` | analyze a dir → suggested command | `--recommend` |
| `install [dir] [flags]` | copy the bundle in (**default** verb — may be omitted) | — |
| `upgrade <dir> [--apply]` | 3-way diff vs. the current bundle; preserves local edits | `--upgrade` |
| `uninstall <dir>` | reverse an install | `--uninstall` |
| `list [--json]` | preview the catalog | `--list` |
| `list-mcps` | list MCP recipes | `--list-mcps` |
| `setup` | guided interactive flow | `-i` / `--interactive` |

Key `install` flags: `--platform apple|android|both` (auto-detected if omitted),
`--apple-language swift|objc|both`, `--features recommended|all|<csv>`,
`--agents claude,copilot,cursor,gemini,codex,kiro|all`, `--with-mcps <csv>`,
`--new` (create the dir + `git init`), `--dry-run`.

## The three situations `recommend` resolves

- **missing** dir → `install <dir> --new …` — makes the dir + `git init` (it does **not** generate an Xcode/Gradle project).
- **fresh** / **unmanaged** dir → `install <dir> …` — adopt; refreshes files and writes a manifest (becomes upgrade-able).
- **managed** dir (has `.claude/.appbootstrap-manifest.json`) → `upgrade <dir> --apply`.

A plain `install` over a **managed** dir is refused (use `upgrade`; `--force` overrides). `recommend` picks the right one for you.

## What `recommend` keys on (framework → feature category)

`import FoundationModels` → `ai` · Core Data / SwiftData / `.xcdatamodeld` →
`persistence` · RealityKit / `.usdz` → `spatial` · Room → `persistence` ·
R8 / ProGuard → `shrinking` · XML layouts / Fragments → `migration` ·
fastlane / CI → `deployment`. The `recommended` set is always included.

## Guardrails (respect these)

- The installer **never overwrites** `CLAUDE.md`, `settings.json`, or existing
  agent files — it prints what it skipped. Don't work around that.
- `upgrade` keeps locally-edited files (3-way diff); only `--force-conflicts` overrides.
- **Committing and pushing are the user's call.** Edit the working tree freely;
  do not `git commit` / `git push` unless the user explicitly asks.
- Prefer `--dry-run` / the `preview_*` tools before any write.
- Don't broaden `--features` past what the repo uses — extra categories cost the
  user context tokens. Trust `recommend`'s feature list.

## Via MCP

This repo ships an MCP server (`mcp-server/`) exposing the same surface as typed
tools — call **`recommend_setup`** first, then `preview_install` / `install`,
`preview_upgrade`, `preview_uninstall` / `uninstall`, plus `list_categories` /
`list_rules` / `list_skills`. See [mcp-server/README.md](mcp-server/README.md).

## Don't

- Don't hand-copy rules or skills — always go through `install.sh`.
- Don't re-install over a managed repo — use `upgrade`.
- Don't skip the preview step on a destructive action (`uninstall`, `upgrade --apply --force-conflicts --prune`).
