# Using the bundle

## How it fires

**Rules** (`.claude/rules/`) load automatically based on each file's `paths:` frontmatter (with a matching `globs:` for Cursor) — Apple rules fire on `*.swift` / `*.{h,m,mm}`, Android rules fire on `*.{kt,kts}` (plus `*.xml` for the localization rule). No invocation needed; they steer Claude as soon as a matching file enters context. Each rule is a short checklist (CI fails any rule over 12 KB); where a topic needs more, the full text lives in the matching skill's `references/` and loads only when that skill runs.

**Skills** (`.claude/skills/`) are deeper review agents that fire on demand. Trigger by description match or invoke explicitly:

- "Use `swift-concurrency-pro` to review `NetworkClient.swift`."
- "Use `swiftui-pro` to check `SettingsView.swift` for modern API and a11y."
- "Use `swift-testing-pro` to write tests for `UserSession`."
- "Use `coredata-swift6-pro` to review `PersistenceController.swift`."
- "Use `swift-docc-pro` to review the public API in `MyPackage`."
- "Use `swift-error-handling-pro` to review my typed throws migration."
- "Use `swift-logging-pro` to audit `Logger` usage across the project."
- "Use `swift-memory-storage-pro` to find why the photo grid gets killed on older iPhones."
- "Use `android-memory-storage-pro` to audit what the app writes to disk and backs up."
- "Use `app-intents-pro` to review our App Intents and make the shopping-list actions work with Siri."
- "Use `xcode-security-pro` to audit our build settings and plan turning on Enhanced Security."
- "Use `instruments-profiling-pro` to find out why the feed hangs on first launch."
- "Use `motion-design-pro` to define our motion tokens and write the motion spec with our designer."
- "Use `motion-design-pro` to review the onboarding animations for timing, consistency, and Reduce Motion."
- "Use `swift-package-pro` to review `Package.swift` and the public API surface."
- "Use `android-gradle-architecture-pro` to review my multi-module Gradle setup."
- "Use `xml-to-compose-migration-pro` to plan migrating `SettingsFragment` to Compose."
- "Use `r8-shrink-pro` to audit my `proguard-rules.pro` for the next release."

Each produces a file-by-file findings report with before/after fixes and a prioritized summary.

## Using AI to install

`install.sh` is a shell command — every coding agent can run it. Agents operating this package should read [`AGENTS.md`](../AGENTS.md) — a terse, machine-first guide to the create / adopt / update workflow. If you'd rather *ask* the agent to bootstrap your repo than run the script by hand, four things make that work well:

1. **Let the package do the analysis: `./install.sh recommend <dir>`.** This is the fastest path for an agent. Point it at any directory and it introspects the repo — managed-state, platform, Apple-language, and framework usage (`import FoundationModels` → `ai`, Core Data / SwiftData → `persistence`, Room → `persistence`, R8/ProGuard → `shrinking`, fastlane/CI → `deployment`, `*Repository` types → `architecture`, …) — then prints the **exact** create / adopt / upgrade command to run, with the reasoning behind each choice. Add `--json` for a machine-readable object (with a ready-to-exec `command` array) instead of prose. One call replaces the agent grepping the tree by hand.

   ```bash
   # Human-readable
   /path/to/AppBootstrapAI/install.sh recommend ~/Projects/MyApp
   # Machine-readable (the agent parses `command` / `preview_command`)
   /path/to/AppBootstrapAI/install.sh recommend ~/Projects/MyApp --json
   ```

   The recommended flow for an agent is **`recommend` → run the suggested `--dry-run` preview → run the real command**.
2. **Hand the agent this repo's URL and your project description.** Most agents need just enough context to pick the right flags. A prompt like *"Bootstrap this iOS+macOS app with AppBootstrapAI — Swift only, include the AI/Foundation Models category"* tells Claude / Cursor / Gemini / Kiro / Copilot what they need to know.
3. **The agent can introspect the catalog before installing.** `./install.sh --list --features all` prints every rule and skill with its category and one-line description. Agents that read the output can recommend the right `--features` list for your project.
4. **For agents that speak MCP** (Claude Code, Cursor, others with MCP client support), this repo ships an [MCP server](../mcp-server/README.md) that exposes the installer as ten structured tools: **`recommend_setup`** (call first — analyze a dir → suggested command), `audit_project`, `list_categories`, `list_rules`, `list_skills`, `preview_install`, `install`, `preview_upgrade`, `preview_uninstall`, and `uninstall`. Wire it into your agent's MCP config and the agent runs the installer through a typed API rather than parsing shell output. It also ships `audit` and `sync_and_audit` prompts. See [`mcp-server/`](../mcp-server/) for setup.
5. **To audit a repo without installing**, ask any agent to *"use github.com/kelvinkosbab/AppBootstrapAI to audit this repo"*. It follows [`playbooks/audit.md`](../playbooks/audit.md) and runs `install.sh audit <dir> --no-install-check`, which also knows the difference between a library (Swift package, Android library: store-only checks skipped, `swift-package-pro` / `android-gradle-architecture-pro` suggested) and an app. Nothing is written to the repo unless you ask.
6. **To update and audit an existing project with any agent** (Claude, Gemini, Codex, …), type **`/appbootstrap-sync`** in the repo. The install writes that command for Claude Code (`.claude/commands/`), Cursor (`.cursor/commands/`), Copilot (`.github/prompts/`), and Gemini CLI (`.gemini/commands/`); it finds the bundle through `bundle` in the manifest and runs [`playbooks/sync-and-audit.md`](../playbooks/sync-and-audit.md): sync the bundle, run `install.sh audit`, triage each finding against its rule, run the listed skills, and write a report. For one area, **`/appbootstrap-audit <topic>`** (for example `concurrency` or `accessibility`) runs a read-only audit that loads only that topic's rules and skills. `install.sh audit . --fail-on high` gates CI on the same checks; on an existing codebase, run `install.sh audit . --write-baseline --baseline-reason "…"` once so CI fails only on new findings.

**Recommended prompts** (copy-paste-friendly for the agent of your choice):

| Goal | Prompt |
|------|--------|
| Audit a repo without installing | *"Use github.com/kelvinkosbab/AppBootstrapAI to audit this package. Don't change any files."* |
| Review and improve your AI rules | *"Use github.com/kelvinkosbab/AppBootstrapAI to audit our CLAUDE.md, AGENTS.md, and Cursor rules and suggest improvements."* (`install.sh audit . --steering-only`) |
| Audit one area only, reading just its rules and skills | *"Use github.com/kelvinkosbab/AppBootstrapAI to audit only the concurrency safety of this repo."* (`/appbootstrap-audit concurrency` after an install, or `install.sh audit . --topic concurrency`; topics: concurrency, architecture, accessibility, ui, localization, testing, compliance, logging, docs, deployment, linting, memory, storage, intents, security, performance, motion) |
| Bootstrap a new Apple SwiftUI app with the recommended set | *"Run `/path/to/AppBootstrapAI/install.sh . --platform apple` in this directory, then walk me through what landed."* |
| Bootstrap an Android Compose app with everything | *"Run `/path/to/AppBootstrapAI/install.sh . --platform android --features all` and summarize the new files."* |
| Pick categories interactively | *"Show me `./install.sh --list --features all`, then ask me which categories to install."* |
| Cross-platform monorepo with specific features | *"Bootstrap this repo for both Apple (Swift) and Android. Include `core`, `testing`, `docs`, `concurrency`, `ui`, and `localization`."* |
| Mixed-language Apple project (Swift + ObjC) | *"Run `./install.sh . --platform apple --apple-language both --features all`."* |

Agents that run in a terminal context (Claude Code, Cursor's agent mode, Gemini CLI, Kiro, Codex CLI) execute the shell command directly. Agents without shell access (Copilot Chat, web Claude.ai) can produce the command for you to run.

## Building with AI agents (after install)

Installing the bundle is step one; the payoff is how your agent behaves while you build. A few habits get the most out of it:

1. **Rules steer the agent's output — but most are review-time conventions, not compiler-enforced.** The agent writes to the rules automatically, yet several say so outright (*"enforced by review, not the compiler"*). Review what lands, and when the agent slips, *name the rule*: *"this violates `apple-swiftui-mvvm.md` — fix the ownership."* Citing the file points the agent at the exact text and it self-corrects.
2. **Invoke the deep-review skills explicitly — don't wait for auto-fire.** Skills (`.claude/skills/`) are on-demand review agents that load only when asked. After the agent writes a feature, request the matching review: *"Use `swiftui-pro` to review `SettingsView.swift`"*, *"Use `android-compose-pro` to check `FeedScreen.kt` for recomposition bugs"*, *"Use `swift-accessibility-pro` to audit the onboarding screens before we claim VoiceOver support on the App Store."* Each produces a file-by-file findings report with before/after fixes.
3. **Skills reach Claude Code and Android Studio; other agents get the rules as steering.** Cursor, Copilot, Gemini CLI, Codex, and Kiro receive the rules in their native format (see [Using with non-Claude AI agents](agents.md)) but not the deep-review skills. With those agents, ask for a manual pass instead: *"Review this against `.claude/rules/android-coroutines-best-practices.md`."*
4. **Keep sessions scoped — it's correctness *and* token economy.** Rules are glob-scoped, so only the ones matching the files you're touching load into context. A focused session (one subsystem, its relevant rules) gives sharper steering and a smaller bill than a sprawling one. More in [Saving AI tokens](using-the-bundle.md#saving-ai-tokens).
5. **Put project-specifics in `CLAUDE.md`.** The agent reads it first. The module graph, build commands, and gotchas you record there compound with the bundle's rules — and a pattern you catch yourself correcting twice belongs in a new `.claude/rules/<name>.md`.
6. **On Android, add Google's official skills and the Android CLI.** [android/skills](https://github.com/android/skills) (Apache-2.0) covers areas this bundle leaves to Google: ANR triage, profiling, Intent and permission security, Navigation 3, AGP 9 upgrades, Play policy, Wear, and Glance. Install it next to the bundle with `android skills add --all --project=.` or, in Claude Code, `/plugin marketplace add android/skills`. Where the two overlap (`r8-shrink-pro`, `android-adaptive-layout-pro`, `android-compose-pro`, `android-memory-storage-pro`, `xml-to-compose-migration-pro`, `store-compliance-pro`), each bundle skill says which official skill to use for what. The [Android CLI](https://developer.android.com/tools/agents/android-cli) gives agents `android docs search` and `fetch` for current docs and `android studio find-usages` for code navigation; `android-project-rules.md` says when to use it, and `settings.json` allows its read-only commands.
7. **Stay current.** New platform APIs land in the rules each Xcode / AGP cycle. Run `upgrade` periodically so the steering reflects them — see [Upgrading an existing install](upgrading.md).

## Saving AI tokens

AI agents pay for every token of context they load. This bundle has a few levers to keep your context bill small without losing functionality. The savings are mostly small individually but compound across long sessions.

### At install time

- **Let auto-detect pick `--platform` for you.** Run `./install.sh .` with no `--platform` flag from inside your project and the installer sniffs the directory: `Package.swift` / `*.xcodeproj` → apple; `build.gradle*` / `gradlew` → android; both present → both; neither → falls back to `both`. The chosen platform + matched signals print in the install header so you can verify. A Swift-only iOS repo lands with just Apple rules in `.claude/rules/`, no Android cruft.
- **Override `--platform` only when detection is wrong.** Auto-detect picks based on what's in the target dir today; an explicit `--platform apple|android|both` always wins. Use this when bootstrapping a fresh empty repo (otherwise the fallback is `both`, which is too broad if you know it's iOS-only).
- **Stick to `--features recommended` (default).** Specialized categories — `persistence` (Core Data), `ai` (Foundation Models), `migration` (XML→Compose), `shrinking` (R8) — only load when you opt in. If your app doesn't use Core Data, the `coredata-swift6-pro` skill is wasted catalog space.
- **Pure-Swift project? Keep `--apple-language swift` (the default).** That skips the two `apple-objc-*` rules. Only switch to `both` if you have genuine `.h`/`.m`/`.mm` files; switch to `objc` for legacy ObjC-only codebases.
- **Not a visionOS app? The default already excludes it.** `--apple-platforms` defaults to `ios,macos,tvos,watchos` — so the visionOS rule stays out unless you name `visionos` (or pass `--features …,spatial`). Building for visionOS? `--apple-platforms ios,visionos` pulls it in. **iOS-only?** `--apple-platforms ios` also drops the touch-on-Mac rule (`apple-mac-touch.md`). Every other Apple rule is universal across iOS/macOS/tvOS/watchOS.
- **`--with-mcps` only what you'll use this week.** Each MCP entry adds tool metadata to the agent's catalog. If you're not actively using Firebase MCP, don't install it.

When you over-broaden any of these, `install.sh` prints a "Token-saving tips" block at the end suggesting the tighter flag. That's the install-time feedback loop.

### During development

- **Be specific in prompts.** *"Review `Sources/Networking/Client.swift`"* loads one file. *"Review the codebase"* invites the agent to search the whole tree. The first prompt is usually 10–100x cheaper.
- **Invoke skills by name.** *"Use `swift-concurrency-pro` to review X.swift"* loads that one skill's references. Asking general questions can trigger speculative skill loads — sometimes several at once.
- **Truncate build-log paste-ins.** When a build fails, paste the failing 20–50 lines plus the function signature, not 500 lines of unrelated warnings. (Documented in detail in `apple-objc-best-practices.md` for the mixed-language case; same principle for any language.)
- **Audit one area at a time.** `/appbootstrap-audit <topic>` (or `install.sh audit . --topic <topic>`) loads only that topic's rules and skills instead of the whole bundle.
- **One skill at a time.** Running multiple deep-review skills back-to-back in the same turn forces the agent to hold all of their reference docs in context simultaneously. Sequence them across turns.

### Long-running

- **Keep your project's `CLAUDE.md` focused.** It loads on every session. Stale sections and aspirational content are pure context tax — prune ruthlessly.
- **Periodically run `./install.sh --list`** to see what's installed vs. what's available. If you've stopped using a category (e.g., you've fully migrated off XML→Compose), re-run install without it to drop the `migration` rules and `xml-to-compose-migration-pro` skill.
- **Use the MCP server for agent-driven installs.** If you're asking an agent to bootstrap a new repo, the [MCP server](../mcp-server/README.md) returns structured JSON (`list_categories`, `list_rules`, `list_skills`) — cheaper for the LLM to consume than parsing the catalog's plain-text format.

### What this won't save

To set expectations honestly: scoping the install down won't dramatically cut your bill if your prompts are already loose. Rules with `paths:` only attach to context when matching files are in the conversation — Android rules in an iOS-only repo are effectively dormant whether or not they're installed. The bigger wins come from prompt discipline and explicit skill invocation, not from install-flag micro-optimization.
