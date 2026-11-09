# AppBootstrapAI

A drop-in bundle of **AI agent steering** — rules, skills (Claude), and MCP recipes — for bootstrapping new app projects. Covers Apple platforms (iOS, macOS, tvOS, watchOS, visionOS) and Android in one bundle, so single-platform and mixed-stack teams can share one source of truth. Works with **Claude Code, GitHub Copilot, Cursor, Gemini CLI, Codex CLI, and Kiro** out of the box (`./install.sh --agents <name>` writes the right files per agent).

One `install.sh` bootstraps modern review, testing, style, accessibility, localization, and regional store-compliance guidance into any new or existing app repo — and keeps it up to date with `--upgrade`. Day-one consistency without writing the rules yourself; day-N reproducibility without drifting from upstream.

**Claude Code is the default target, but the installer can write for other agents too.** Pass `--agents copilot,cursor,gemini,codex,kiro,android-studio` (or `all`) and `install.sh` drops the right file shape per agent: `.github/instructions/*.instructions.md`, `.cursor/rules/*.mdc`, `GEMINI.md`, `AGENTS.md`, `.kiro/steering/*.md`, and for Android Studio `.agents/skills/` plus `.aiexclude`. Every agent gets rules scoped to the files they cover; Gemini, Codex, and Android Studio, which can't scope by path, get a short index that names the rule to read for each file type. Skills go to Claude Code and Android Studio. For Cline / Goose / Roo / Windsurf etc., layer a sync tool — see [docs/agents.md](docs/agents.md).

**Audit without installing:** see [Audit a repo](#audit-a-repo). Agents: start at [`AGENTS.md`](AGENTS.md).

**Get started in one line:** `./install.sh setup` runs a guided flow that detects whether you're creating, adopting, or updating — and walks you through the rest. Prefer flags? See [Getting started](#getting-started).

## Contents

[What you get](#what-you-get) · [Getting started](#getting-started) · [Audit a repo](#audit-a-repo) · [Documentation](#documentation) · [Roadmap](#roadmap) · [Credits](#credits)

## What you get

| Area | What's inside |
|------|---------------|
| **Apple rules** | Swift 6 concurrency · SwiftUI MVVM · design system + iconography · motion design · adaptive layout / iPhone Duo · touch on Mac · accessibility · testing · DocC · localization · SPM + modular architecture · repository pattern (opt-in) · linting · logging · memory + storage · App Intents + Siri (opt-in) · Xcode build security (opt-in) · Foundation Models · visionOS · TestFlight · regional App Store compliance · Objective-C |
| **Android rules** | Kotlin/Compose/MVVM/Hilt · modular architecture · MVVM + repository pattern (opt-in) · coroutines · design system + iconography · motion design · accessibility · large screens / foldables / desktop windows · testing · KDoc · localization · Gradle · linting · logging · memory + storage · Gemini Nano / Firebase AI · Play beta · regional store compliance |
| **Skills (Claude)** | On-demand deep-review agents for both platforms |
| **Agents** | One rule source → Claude Code, Copilot, Cursor, Gemini, Codex, Kiro, Android Studio |
| **MCP recipes** | XcodeBuildMCP · Xcode-native · android-mcp-server · Firebase · Sentry |
| **Lifecycle** | guided `setup` · `install` · `upgrade` (3-way diff — never clobbers your edits) · `uninstall` |

The full list of rules and skills, with counts and categories, is in
[docs/catalog.md](docs/catalog.md) (generated from the frontmatter). Run
`./install.sh --list --features all` for the same catalog in a terminal.

The default `--features recommended` set covers what most apps need on day one.
Specialized categories (`persistence`, `ai`, `migration`, `shrinking`,
`spatial`, `deployment`, `architecture`, `intents`, `security`) are opt-in.

## Getting started

The installer takes a **command verb** — `install` (the default, so it can be
omitted), `upgrade`, `uninstall`, `list`, `list-mcps`, or `setup`. Three ways in,
depending on where you are. Not sure which? Run **`setup`** and it figures it out:

```bash
# Guided, prompt-driven — detects create vs. adopt vs. update and walks you
# through platform, features, agents, and MCP recipes with sensible defaults.
/path/to/AppBootstrapAI/install.sh setup
```

> **Verbs and flags are interchangeable.** Every verb has a legacy flag alias —
> `upgrade` == `--upgrade`, `uninstall` == `--uninstall`, `list` == `--list`,
> `setup` == `-i` / `--interactive`. Existing scripts that use the flag form keep
> working unchanged.

### 1. New project (green-field)

Create the directory, `git init` it, and install the bundle in one step:

```bash
/path/to/AppBootstrapAI/install.sh install ~/Projects/MyNewApp --new --platform apple
```

`--new` makes the target dir (and parents) and initializes a fresh git repo,
then installs. It's light scaffolding — it does **not** generate an Xcode or
Gradle project; create that with Xcode / Android Studio, then commit.

### 2. Existing project (adopt)

Point the installer at your repo root. Platform auto-detects from the files
already there (`install` is the default verb, so you can omit it):

```bash
cd /path/to/your/app
/path/to/AppBootstrapAI/install.sh .
```

Nothing you've authored gets overwritten — an existing `CLAUDE.md`,
`settings.json`, or agent file is left alone and the installer prints what it
skipped so you can merge by hand.

### 3. Update an existing install

Once a repo is managed (it has a `.claude/.appbootstrap-manifest.json`), use
`upgrade` — never a plain re-install:

```bash
/path/to/AppBootstrapAI/install.sh upgrade .           # plan-only preview
/path/to/AppBootstrapAI/install.sh upgrade . --apply   # execute the plan
```

`upgrade` runs a 3-way diff (what was installed vs. your current files vs. the
latest bundle) so your local edits are preserved. A plain `install` over a
managed repo is **refused** with guidance to use `upgrade` — that guard stops
a re-install from silently resetting the manifest baseline. If you genuinely
want to re-install over a managed target, pass `--force`. More in [docs/upgrading.md](docs/upgrading.md).

## Audit a repo

Read-only, nothing installed:

```bash
/path/to/AppBootstrapAI/install.sh audit /path/to/repo --no-install-check
```

It reports rule hotspots (each mapped to the rule and skill that cover it) and
reviews the repo's own AI steering files. Or ask any agent: *"Use
github.com/kelvinkosbab/AppBootstrapAI to audit this repo."* It follows
[`playbooks/audit.md`](playbooks/audit.md). After an install,
`/appbootstrap-sync` updates and audits in one step, and
`/appbootstrap-audit <topic>` audits one area. `install.sh audit . --fail-on high`
gates CI on the same checks.

## Documentation

| Page | What's in it |
|---|---|
| [docs/catalog.md](docs/catalog.md) | Every rule and skill, by platform and category |
| [docs/install-reference.md](docs/install-reference.md) | Every `install.sh` command and flag, with examples |
| [docs/using-the-bundle.md](docs/using-the-bundle.md) | How rules and skills fire, installing with an AI agent, working with agents after install, saving tokens |
| [docs/upgrading.md](docs/upgrading.md) | `upgrade` (3-way diff, renames, MCP entries) and `uninstall` |
| [docs/agents.md](docs/agents.md) | Copilot, Cursor, Gemini, Codex, Kiro, and Android Studio file layouts |
| [docs/mcp-tooling.md](docs/mcp-tooling.md) | Companion MCP servers for Apple, Android, and both |
| [docs/verify-on-sdk.md](docs/verify-on-sdk.md) | Beta SDK symbols the rules cite, to re-check at each Xcode release |
| [mcp-server/](mcp-server/README.md) | This repo's MCP server: the installer as typed tools |
| [AGENTS.md](AGENTS.md) | The create / adopt / update workflow, for agents |
| [CLAUDE.md](CLAUDE.md) | Repo layout and how to write new rules and skills |
| [CHANGELOG.md](CHANGELOG.md) | Release notes ([Keep a Changelog](https://keepachangelog.com)) |

## Roadmap

**Next — closing the day-one gaps for new app developers:**

- Navigation rules for both platforms (`NavigationStack` / Navigation-Compose) — the first architectural decision a new app makes, and where AI agents still emit deprecated patterns.
- Apple app-target hygiene (dev signing, simulator-vs-device) and Android permissions/manifest + persistence (Room / DataStore) rules.
- `android-testing-pro` (JUnit/MockK/Turbine/Compose-test review) to match `swift-testing-pro`.
- Networking and release-readiness review skills; a day-one walkthrough from empty directory to first build.
- Git task-switching + merged-branch cleanup shortcuts (rule + `scripts/` installer).

## Credits

- Apple skills authored by **Paul Hudson** ([@twostraws](https://github.com/twostraws)) and licensed MIT. Original sources, linked from the bundled skill references:
  - [`swift-concurrency-agent-skill`](https://github.com/twostraws/swift-concurrency-agent-skill)
  - [`swift-testing-agent-skill`](https://github.com/twostraws/swift-testing-agent-skill)
  - [`swiftui-agent-skill`](https://github.com/twostraws/swiftui-agent-skill)
  - [`swiftdata-agent-skill`](https://github.com/twostraws/swiftdata-agent-skill)
  - …and more on his profile. Author attribution is retained in each `SKILL.md` frontmatter.
  - Bundled copies track upstream; `swiftui-pro` is synced to upstream 2.0.0 (Xcode 27.2 / iPhone Duo).
- Android skills (`android-gradle-architecture-pro`, `xml-to-compose-migration-pro`, `r8-shrink-pro`) authored by AppBootstrapAI contributors. Grounded in [Android's Now in Android](https://github.com/android/nowinandroid) reference app and the official [Android Developers documentation](https://developer.android.com/build) for AGP, Compose, and R8 — the canonical primary sources. Licensed MIT.

- App Intents, Siri, Xcode security, Instruments profiling, and parts of the accessibility, adaptive-layout, and testing guidance draw on the agent skills Apple ships with Xcode 27, which **Artem Novichkov** ([@artemnovichkov](https://github.com/artemnovichkov)) extracted and published in [`artemnovichkov/xcode-skills`](https://github.com/artemnovichkov/xcode-skills). Thank you, Artem, for making them readable outside Xcode. The underlying content is Apple's and that repository has no license, so nothing is copied: the guidance here is rewritten and condensed in this bundle's own words, and every file that draws on it credits Artem's repository in a **Sources** note. Files: `apple-app-intents.md`, `apple-build-security.md`, and `apple-testing-strategy.md` (rules); `app-intents-pro`, `xcode-security-pro`, and `instruments-profiling-pro` (skills); `swift-accessibility-pro/references/nutrition-label-audit.md`, `swift-adaptive-layout-pro/references/uikit-api-replacements.md`, and `readiness-checklist.md`.

- Motion design guidance (`apple-motion-design.md`, `android-motion-design.md`, and the `motion-design-pro` skill) is adapted from the [motion design skill](https://github.com/lottiefiles/motion-design-skill) by **LottieFiles** ([@LottieFiles](https://github.com/LottieFiles)), MIT-licensed, © 2025 LottieFiles. Thank you, LottieFiles, for publishing it openly. Its principles, timing tables, and patterns are rewritten for SwiftUI and Jetpack Compose and checked against Apple's and Material 3's motion guidance; each file that draws on it credits LottieFiles in a **Sources** note, and the MIT notice ships in `.claude/skills/motion-design-pro/NOTICE.md`.

## License

MIT — see [LICENSE](LICENSE).
