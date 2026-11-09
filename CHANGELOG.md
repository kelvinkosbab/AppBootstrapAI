# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org).
The `1.0.0` section reconstructs the bundle's capabilities from pre-tag history.

## [Unreleased]

### Added

- **npm publishing.** A release tag also publishes
  `@kelvinkosbab/appbootstrap-mcp` to npm with provenance, at the tag's
  version and with the bundle packed inside. It needs an `NPM_TOKEN`
  repository secret and skips with a warning without one. The release
  workflow can be re-run by hand from a tag to finish a release; steps that
  already happened are skipped.
- **`docs/verify-on-sdk.md`**, a checklist of the Xcode 27 beta and
  point-release symbols the rules and skills cite (symbol, files, last
  verified seed), to re-check at each Xcode release.

- **Five skills that hold that detail:** `linting-pro`, `localization-pro`,
  and `beta-deployment-pro` (either platform), plus `foundation-models-pro`
  and `visionos-pro` (Apple). Each installs with its rules' feature category,
  and the `linting`, `localization`, and `deployment` audit topics include
  them. `store-compliance-pro` gains `apple-storefronts.md` and
  `android-countries.md`.

### Changed

- The MCP server's version now follows the bundle (`1.1.0`) and is read from
  `package.json` instead of being hard-coded.

- **Ten more rules slimmed to must-lists.** The Apple linting, localization,
  Foundation Models, visionOS, TestFlight, and regional-compliance rules and
  the Android linting, localization, Play beta, and regional-compliance rules
  now hold only their checklists (about 3 KB each, down from 11–24 KB). The
  full text moved, unchanged, into skill references. `OVERSIZED_RULES` now
  lists only `apple-objc-accessibility-best-practices.md`.
- Audit findings for SwiftLint, ktlint, RTL, `Text` literals, and privacy
  manifests now point at the matching new skill.

## [1.1.0] - 2026-11-09

### Added

- **Release workflow.** Pushing a `vX.Y.Z` tag runs every check on the tagged
  commit, requires a matching CHANGELOG section, and publishes the GitHub
  release with that section as its notes.
- **Swift 6.2 app-package settings.** `scaffold-spm-package.sh --main-actor
  <csv|all>` writes a tools-6.2 manifest with `.defaultIsolation(MainActor.self)`
  on UI and feature modules plus `NonisolatedNonsendingByDefault` and
  `InferIsolatedConformances`; Core stays nonisolated. The template gains the
  same variant, a `swiftSettings:` parameter on `makeTargets()`, and
  `.treatAllWarnings(as: .error)` in place of the `-warnings-as-errors`
  `unsafeFlags` example. `manifest-conventions.md` and the SPM and
  concurrency rules say when to use it.
- **`Package.swift` audit checks:** `spm-unsafe-flags` and
  `spm-unpinned-dependency` (libraries), `spm-lint-plugin-inherited`,
  `spm-no-language-mode`, `spm-no-platforms`, `build-ld-classic`,
  `spm-implementation-only`, `spm-library-resolved-tracked`, and
  `spm-app-resolved-ignored`.
- **Unit tests for the audit checks** (`tests/test_audit.py`, plain
  `unittest`): every line check needs a matching and a non-matching sample.
- **`swift` CI workflow** that scaffolds packages (default and
  `--main-actor`), runs `swift build` and `swift test` on them, and builds
  the template, in a `swift:6.2` container.

- **Motion design**, adapted from the LottieFiles
  [motion design skill](https://github.com/lottiefiles/motion-design-skill)
  (MIT, © 2025 LottieFiles) and rewritten for SwiftUI and Jetpack Compose. In
  `ui` (so in `recommended`):
  - `apple-motion-design.md` and `android-motion-design.md` rules: purpose
    before properties, motion tokens in the design-system module, timing and
    easing by element, render-only animation, capped stagger, haptics,
    reduced-motion alternatives, and Lottie playback.
  - `motion-design-pro` skill (either platform) for designers and
    developers: motion personality and tokens, a `docs/design/motion.md` spec
    template, Lottie / dotLottie handoff, recipes with SwiftUI and Compose
    sketches, and a review checklist. The MIT notice ships in its `NOTICE.md`.
  - Audit topic `motion` and the `swift-motion-loop-no-reduce-motion` /
    `kt-motion-loop-no-reduce-motion` checks (a looping animation in a file
    that never reads the reduced-motion setting).

- **Knowledge from Apple's Xcode 27 agent skills**, as extracted and published
  by Artem Novichkov in
  [`artemnovichkov/xcode-skills`](https://github.com/artemnovichkov/xcode-skills).
  That repository has no license and its content is Apple's, so the guidance
  is rewritten in this bundle's words and each file credits it.
  - `intents` category (opt-in): `apple-app-intents.md` rule and
    `app-intents-pro` skill (execution and results, entities and queries,
    parameters and App Shortcuts, iOS 26 / 27 APIs, Siri 27.3 tools and app
    skills, `AppIntentsTesting`, SiriEvaluations).
  - `security` category (opt-in): `apple-build-security.md` rule and
    `xcode-security-pro` skill (security warnings, analyzer checks, Enhanced
    Security, hardened-process entitlements, phased rollout, C bounds safety).
  - `performance` category (in `recommended`): `instruments-profiling-pro`
    skill (`xctrace` recording and reading, call trees, symbolication, hang
    triage).
  - Audit topics `intents`, `security`, and `performance`, and four
    `install.sh audit` checks: `openAppWhenRun`, `@Assistant*` macros, and
    `ENABLE_POINTER_AUTHENTICATION = NO` / `ENABLE_ENHANCED_SECURITY = NO` in
    `.xcconfig` files (now scanned).
  - `swift-accessibility-pro` gains `nutrition-label-audit.md` (per-screen
    PASS / FAIL / NEEDS VERIFICATION for VoiceOver, Larger Text, and
    Sufficient Contrast); `swift-adaptive-layout-pro` gains
    `uikit-api-replacements.md` and launch-screen (ITMS-90870), iPad
    orientation, and `UIRequiresFullScreen` (TN3192) checks.

- **Memory and storage.** A new `memory-storage` category (in
  `recommended`) with four short checklist rules,
  `apple-memory-management.md`, `apple-storage-management.md`,
  `android-memory-management.md`, and `android-storage-management.md`, and
  two audit skills, `swift-memory-storage-pro` and
  `android-memory-storage-pro`, whose references hold the depth (retain
  cycles and leaks, footprint, storage layout, measuring). Two audit topics,
  `memory` and `storage`, split the work; a finding whose rule belongs to one
  of them no longer leaks into the other through the shared skill.
  `install.sh audit` gains checks for target-retaining timers,
  `assign(to:on: self)`, strong delegates, full-size image decodes,
  credentials in UserDefaults or preferences, caches in Documents,
  disk-space and file-timestamp APIs missing from the privacy manifest,
  `StaticFieldLeak`, ViewModels holding UI, `largeHeap`, `commit()`,
  deprecated `security-crypto` and external-storage APIs, Room main-thread
  queries, broad storage and media permissions, Auto Backup without rules,
  and a missing LeakCanary.
- **`install.sh audit --topic <name>`** audits one area. `lib/topics.json`
  maps each topic (`concurrency`, `architecture`) to its rules and skills;
  the audit keeps only that area's findings and deep reviews, skips the
  steering review, and lists the files to read in `topic`, so an agent never
  loads the rest of the bundle for a single-area audit. Topics:
  `concurrency`, `architecture`, `accessibility`, `ui`, `localization`,
  `testing`, `compliance`, `logging`, `docs`, `deployment`, `linting`.
  `validate-frontmatter.py` checks that every rule and skill a topic names
  exists.
- **`/appbootstrap-audit <topic>`** is installed next to `/appbootstrap-sync`
  for Claude Code, Cursor, Copilot, and Gemini CLI. It runs the topic audit
  read-only and reports in chat; with no topic it lists them.

### Changed

- **`/appbootstrap-sync`, `/appbootstrap-audit`, and both playbooks clone the
  latest release tag** instead of the default branch, so an unreleased push to
  `main` doesn't run in adopters' sessions. Ask for the default branch to get
  unreleased changes.
- **CHANGELOG `[Unreleased]` grouped** into one Added / Changed / Fixed set and
  released as 1.1.0.
- **Four long rules are now short checklists**, with the full text moved
  into the matching skill's `references/`: `apple-adaptive-layout`
  (19 KB to 4 KB, full text in `swift-adaptive-layout-pro`),
  `apple-mac-touch` (16 KB to 3 KB, in `swiftui-pro`),
  `apple-modular-architecture` (13 KB to 3 KB, in `swift-modularization-pro`),
  and `android-modular-architecture` (12 KB to 3 KB, in
  `android-modularization-pro`). The rules load whenever a matching file is
  open; the references load only when the skill runs. The Objective-C
  accessibility rule stays whole, because Objective-C-only installs ship no
  skills.
- **Rules have a size budget.** `validate-frontmatter.py` fails a rule over
  12 KB. Seven rules not yet split are allowlisted at their current size,
  rounded up to the next KB, so they can shrink but not grow, and the check
  asks for an entry's removal once its rule fits.

- **`apple-testing-strategy.md`**: on Xcode 27, UI tests can be Swift
  Testing (XCUIAutomation in `@MainActor` suites); XCTest stays only for
  `measure` performance tests and older Xcode. Adds XCTest migration notes.

- **Copilot, Gemini, and Codex no longer load every rule on every request.**
  They used to get one file with the full text of every in-scope rule (about
  180 KB for an Apple install). Copilot now gets one
  `.github/instructions/<rule>.instructions.md` per rule, with `applyTo` set
  from the rule's globs (brace lists expanded), and a short
  `copilot-instructions.md`. `GEMINI.md` and `AGENTS.md` are now an index
  (about 13 KB for an Apple install) that lists each rule's paths and its
  musts, and tells the agent which `.claude/rules/` file to read in full for
  the file it's editing; the installer writes those rules for Gemini and
  Codex too. Every rule now has a `must:` list in its frontmatter (2 to 5
  short lines, the mistakes that cause real bugs or rejections), which
  `validate-frontmatter.py` requires and caps at 600 characters.
  `upgrade --apply` replaces the old files unless you edited them.

- **`apple-spm-package-conventions.md` and `android-gradle-conventions.md`
  are now short checklists** (about 3 KB each, down from 24 KB). Their full
  text moved unchanged into `swift-package-pro/references/manifest-conventions.md`
  and `android-gradle-architecture-pro/references/build-script-conventions.md`,
  which load only during a manifest or build review.

- **Android large screens, updated for Android 17 and desktop windows.**
  `android-large-screen-best-practices.md` now covers Android 17 removing the
  large-screen opt-out (`PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY`),
  `currentWindowAdaptiveInfoV2()` and the large / extra-large width classes,
  Navigation 3 scene strategies, `Posture`, multi-resume and multi-instance,
  desktop windowing, connected displays, and Play's adaptive quality tiers.
  `android-adaptive-layout-pro` gains a `multi-window-and-desktop.md`
  reference. `install.sh audit` flags manifest resizability limits
  (`android-resizability-restricted`), the removed opt-out
  (`android-resizability-optout`), runtime orientation locks
  (`kt-requested-orientation`), device-type checks (`kt-device-heuristic`),
  the deprecated size-class API (`kt-window-size-class-v1`), and display
  metrics used for layout (`kt-display-metrics`). `android-orientation-lock`
  covers every ignored orientation value, and manifests for games are skipped.

- **App-agnostic name check.** The install smoke test fails if the bundle mentions a
  specific company or program (`FORBIDDEN_NAMES`); Kiro is now named without its vendor.

- **Multitasking and multiple windows on iPhone Duo.** `apple-adaptive-layout.md`
  covers Split View and the stacked video layout, multiple windows (none can be
  opened from Duo's outer display, so use `UIWindowScene.ActivationAction` and
  handle activation errors), per-scene state, and scene accessories
  (`CameraCaptureAccessory`). `swift-adaptive-layout-pro` gains a
  `multitasking-and-scenes.md` reference. `install.sh audit` adds three checks:
  orientation-driven layout, force-unwrapped hinges, and symmetric safe-area
  math.

- **Touch on Mac.** New `apple-mac-touch.md` rule (ui, gated by `macos` in
  `--apple-platforms`) for the touchscreen MacBook Pro and Sidecar touch on
  macOS 27: 36pt hit targets without bigger controls, SwiftUI
  `GestureInputKinds` and `directTouchSystemGesturesDisabled()`, touch reveals
  for hover-only controls, AppKit gesture recognizers in place of mouse
  overrides and tracking loops, `NSIsTouchNative`, games, and Sidecar testing.
  `swiftui-pro` gains a `mac-touch.md` review reference, and `install.sh audit`
  flags mouse-method overrides (`swift-mouse-override`) and event-tracking
  loops (`swift-tracking-loop`).

- **AI steering audit.** `install.sh audit` now inventories a repo's AI
  steering files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, Copilot, Cursor, and
  Kiro rules, `.claude/` rules, skills, and settings) and flags stale paths and
  commands, unfilled placeholders, secrets, oversized or duplicated files,
  lines that contradict a bundle rule, unscoped rules, and permissive settings.
  Files the bundle installed are skipped. `--steering-only` audits just these
  files. The new `ai-steering-files.md` rule (core) is the guide, and
  `playbooks/audit.md` gains a steering review step that recommends
  improvements without editing them. The MCP `audit_project` tool returns the
  `steering` block and accepts `steering_only`.

- **Audit without installing.** `playbooks/audit.md` is a read-only workflow
  for an agent told "use kelvinkosbab/AppBootstrapAI to audit my package": clone
  the bundle to a temp dir, run `install.sh audit <repo> --no-install-check`,
  triage, run the deep reviews, and report in chat. The audit now reports
  `kind` (`package` or `app`); libraries skip the compliance-register check and
  get library reviews (`swift-package-pro`, `swift-docc-pro`,
  `android-gradle-architecture-pro`, `r8-shrink-pro`). README and `AGENTS.md`
  point cold-start agents at it; the MCP server adds an `audit` prompt and
  `skip_install_check` on `audit_project`.

- **Agent sync-and-audit flow.** `install.sh audit` scans a repo (read-only) for
  rule hotspots on both platforms (`try!`, `@unchecked Sendable`, `GlobalScope`,
  `print`, raw `android.util.Log`, AI brand names in UI strings, hardcoded API
  keys, missing privacy manifest or scene lifecycle, …), maps each to its rule
  and skill, and lists the skills to run; `--json` for agents, `--fail-on` for
  CI. `playbooks/sync-and-audit.md` is a vendor-neutral workflow any agent can
  follow: sync, audit, triage, deep review, report. The MCP server adds an
  `audit_project` tool and a `sync_and_audit` prompt.

- **`/appbootstrap-sync` command.** The install writes it for Claude Code,
  Cursor, GitHub Copilot, and Gemini CLI (tracked in the manifest, so upgrade
  and uninstall handle it); Codex and Kiro rule files get a pointer instead.
  It runs the sync-and-audit playbook with no bundle path to type.

- **Bundle location in the manifest.** `bundle.path` and `bundle.repo`
  (credentials stripped) let agents find or re-clone the bundle. The MCP server
  now honors `$APPBOOTSTRAP_BUNDLE` and can be packed for `npx` with the bundle
  inside (`npm pack` in `mcp-server/`; not yet published).

- **Audit baseline.** `install.sh audit --write-baseline [--baseline-reason …]`
  accepts current findings into `.claude/appbootstrap-audit-baseline.json` as
  per-file counts with reasons. Accepted findings are reported separately and
  don't trip `--fail-on`; new occurrences do. `--no-baseline` shows everything.

- **Regional store compliance — 2 rules + 1 skill (new `compliance` category,
  in `recommended`).** `apple-regional-compliance.md` and
  `android-regional-compliance.md` cover per-storefront availability, China
  mainland requirements (ICP and generative-AI filings, no third-party AI brand
  names in the app or listing, game licenses, consent-before-collection and
  GMS-free builds for Chinese Android stores), EU trader status, storefront-based
  gating through one `RegionPolicy`, neutral metadata, and answering a regional
  rejection. `store-compliance-pro` audits an app and its listings and drafts
  the fix and reply. Prompted by KozBon's China rejection over ChatGPT mentions.

- **Modular architecture — 1 new rule + 2 skills, and a rewritten Apple rule
  (packaging, in `recommended`).** `apple-modular-architecture.md` now spells
  out the KozBon layout: what must stay in the app target (`@main`, the
  `AppShortcutsProvider`, main-bundle catalogs), interface/implementation
  modules, re-exports, tests under `swift test`, and a module table in
  `CLAUDE.md`. New `android-modular-architecture.md` covers the Now in Android
  layout: module types, the feature `api`/`impl` split, navigation through
  `:app`, Hilt per module, non-transitive R, build flags, and graph
  enforcement. `swift-modularization-pro` and `android-modularization-pro`
  plan a module graph, migrate one module at a time, and audit an existing
  graph with a dependency-rule script.

- **Cross-platform development — 1 rule + 1 skill (core, `--platform both`).**
  `cross-platform-development.md` steers teams building the Apple and Android
  apps together with AI agents: the native-vs-KMP decision, a monorepo with
  per-platform `CLAUDE.md` files, spec-first features, one shared vocabulary
  of names, generated shared contracts, parity tracking, and CI path filters.
  `cross-platform-parity-pro` ports features between platforms, audits drift,
  and sets up the repo. Both install only when `--platform both`.

- **Architecture — 3 rules (new opt-in `architecture` category).**
  `android-mvvm-architecture.md` covers MVVM with unidirectional data flow
  (one `StateFlow<UiState>` per screen, effects as state, `SavedStateHandle`,
  Route vs Screen). `apple-repository-pattern.md` and
  `android-repository-pattern.md` cover the data layer: single source of
  truth, stream vs one-shot APIs, model mapping, error mapping, DI, and fakes.
  Not in `recommended`; opt in with `--features recommended,architecture`.
  `install.sh recommend` suggests it when it finds `*Repository` types.

- **Iconography & design system — 4 rules + 2 skills (ui).** Gives new apps a
  UI foundation to start from and existing apps a path off hardcoded colors,
  fonts, and one-off components. `apple-iconography.md` puts SF Symbols behind a
  typed `AppIcon` facade (a misspelled or too-new symbol otherwise renders
  nothing, silently), sizes icons through font rather than frames, and covers
  custom symbols and Icon Composer app icons with their Liquid Glass
  appearances. `apple-design-system.md` covers role-named tokens, Dynamic
  Type-safe custom fonts, component styles over wrapper views, and Liquid Glass
  adoption. `android-iconography.md` moves UI glyphs to Material Symbols
  drawables behind an `AppIcons` object and pins the launcher (adaptive +
  monochrome), notification, and splash icon specs. `android-design-system.md`
  covers a Material 3 `AppTheme` with dynamic color, extended tokens via
  CompositionLocal, thin M3 component wrappers, and edge-to-edge.
  `swift-design-system-pro` and `android-design-system-pro` each scaffold the
  design-system module or audit an existing app and return an incremental
  migration plan.

- **Apple adaptive layout & iPhone Duo — rule + skill.**
  `apple-adaptive-layout.md` (ui) covers the platform shift that landed with the
  iOS 27 SDK: **apps are resizable by default** and the **UIScene lifecycle is
  mandatory** (legacy-lifecycle apps no longer launch), so adaptive layout stops
  being an iPad refinement. Steers to size classes over idiom / orientation /
  `UIScreen.main` (iPhone Duo's inner display reports regular-regular while
  still being an iPhone), the containers that adapt for free,
  `ArrangementView` / `UIArrangementViewController` + hinge and reserved-region
  APIs (iOS 27.1), asymmetric safe areas, state continuity across fold, camera
  coordinators, and Device Hub / Previews resize testing.
  `swift-adaptive-layout-pro` audits the same surface in depth — launch
  blockers first, then branching, arrangement nesting constraints, safe-area
  math, and outer→inner navigation continuity. Apple counterpart to
  `android-adaptive-layout-pro`.

- **`apple-infoplist-localization.md`** (localization) — Info.plist strings are
  the one localization channel the type-safe `Strings` facade cannot reach (the
  system reads them, so there's no call site), which left adopting projects with
  no valid path for app names and permission purpose strings. Covers
  `InfoPlist.xcstrings` vs legacy `InfoPlist.strings`, the `INFOPLIST_KEY_*`
  build setting as the required base value (omit it and the upload fails
  `ITMS-90683` even though the key looks present), catalog rows left in the
  *new* state silently shipping the development language, one catalog per
  target, identifiers that must never be translated, and purpose strings
  specific enough to pass App Review.

- **Adaptive layout refreshed for Xcode 27.2.** Xcode 27.2 is now the
  recommended toolchain for iPhone Duo, since its iOS 27.2 SDK includes the
  27.1 APIs. The rule and skill cover two changes existing code feels on the
  27.1+ SDK: `UIView` layout margins default to zero, and iOS 27.1 APIs need a
  `#if !targetEnvironment(macCatalyst)` guard in Catalyst targets. They also
  add the UIKit hinge and reserved-region APIs, vertical-bar item ordering and
  overflow, and Device Hub's 27.2 additions and Duo known issues.

- **`swiftui-pro` synced to upstream 2.0.0** (Paul Hudson's
  [`swiftui-agent-skill`](https://github.com/twostraws/swiftui-agent-skill),
  Xcode 27.2 / iPhone Duo update). Adds `resizability.md`, `localization.md`,
  and an opt-in `performance-plus.md` for deep performance reviews, and
  refreshes the other references for iOS 27 APIs and toolbars.
- **`swift-testing-pro` synced to upstream**: `.serialized` on a suite now
  serializes every test and sub-suite, not just parameterized ones.

- **iPhone Duo support refreshed against the shipped Xcode 27.1 / iOS 27.1 SDK.**
  The original rule was written from release-candidate material and hedged its
  API spellings; several were imprecise. Corrected and expanded:
  `ArrangementView`'s real shape (trailing `secondary:` closure +
  `.arrangementViewStyle(.split/.overlay)`), `onHingeChange`'s context with an
  **optional** `hinge` (most devices have none — force-unwrapping is a bug) plus
  the rule that layout must never key off the raw angle, reserved regions as
  `proxy.reservedRegions(kind: .division / .occlusion)` with `.isActive` (replacing
  the guessed `ReservedRegion` type), the previously-missing vertical-toolbar axis
  APIs (`.axisBehavior`, `toolbarVerticalEdge`, `.toolbarVerticalBehavior`), and
  `ViewThatFits`. Folded↔unfolded **continuity** is now its own section — navigation
  depth, first responder, scroll, playback, in-flight work, session identity, and
  visual stability, with the SwiftUI/UIKit failure modes for each. Testing gains the
  simulator specifics (⌥ Option hinge-angle slider) and, importantly, **what the
  simulator can't cover** (camera transitions, reachability, haptics, thermals).
  `swift-adaptive-layout-pro` updated to match.

- **`apple-testflight-deployment.md` — age declaration & age assurance.** New
  submission-gate section: the social-media capability declaration required on
  every new app and update as of September 2026, gating social features behind
  the `DeclaredAgeRange` API, the regional age-assurance rules already in force
  (Brazil / Australia / Singapore, Utah, Louisiana), and the current-privacy-
  documentation requirement. Xcode 27 toolchain notes gain Device Hub (which
  replaced the Simulator and Devices & Simulators windows) and a warning that
  an SDK bump to iOS 27 is itself a UI-affecting change.

- **Android large screens & foldables — rule + skill, the first form-factor
  gate.** `android-large-screen-best-practices.md` (ui) steers toward window
  size classes over device heuristics (`isWidthAtLeastBreakpoint`,
  `BREAKPOINTS_V2`), Material 3 adaptive canonical layouts, `FoldingFeature`
  posture (tabletop / book), state survival across fold/unfold, large-screen
  input, and the **Android 16 change that ignores orientation / resizability
  restrictions on ≥ 600dp screens** (opt-out removed at targetSdk 37).
  `android-adaptive-layout-pro` audits size-class usage, canonical-layout fit,
  posture handling, manifest restrictions, window-vs-display math, camera
  orientation, hardware input, and maps findings to Play's large-screen quality
  tiers. Both install only when `tablet` is in `--android-platforms` (the
  default) — `--android-platforms` now gates content, as `--apple-platforms`
  does for visionOS. `--help`, the guided setup, the MCP tool descriptions, and
  README no longer describe the selector as a no-op.

- **`swift-accessibility-pro` + `android-accessibility-pro` skills** (ui, in
  `recommended`) — the first accessibility deep-review skills, one per
  platform. Each audits three surfaces with per-surface references: the screen
  reader tree (VoiceOver labels/traits/merging/rotor/announcements; TalkBack
  semantics/roles/live regions incl. the Android 16 announcement migration),
  Bluetooth assistive input (Full Keyboard Access / external keyboards, Switch
  Control / Switch Access scan order, braille-display label quality), and
  visual accessibility (WCAG AA contrast in both themes, Dynamic Type / sp
  scaling, color-independence, reduce motion). Findings are tagged with the
  affected assistive tech and severity by user impact; the Apple skill also
  verifies App Store Accessibility Nutrition Label claims.
- **Color & Contrast sections in both Apple a11y rules** — closes the gap where
  only the Android rule had contrast guidance: WCAG AA ratios, both-theme
  auditing, semantic colors over hex, Increase Contrast /
  `shouldDifferentiateWithoutColor`, and Smart Invert (`accessibilityIgnoresInvertColors`).

- **`apple-modular-architecture.md`** (packaging, in `recommended`) — steers
  Apple apps toward a thin Xcode app target over a fat local Swift package split
  into many small modules (the KozBon / BasicSwiftUtilities shape). Covers why
  it wins, the layered dependency graph (Core → domain → features → UI →
  `AppCore` umbrella), the incremental migration playbook, and the
  `Bundle.module` / `.xcdatamodeld` caveats. Complements the existing
  `apple-spm-package-conventions.md` (manifest mechanics).
- **`scripts/scaffold-spm-package.sh`** — generates a KozBon-style local package
  (`<App>Packages/`) so an existing app can modularize: a `makeTargets()`-based
  `Package.swift` from `--modules Core,…,AppCore` plus a compiling source +
  passing Swift Testing placeholder per module, with an `AppCore` umbrella the
  app links. Non-destructive (`--dry-run` / `--force`, never overwrites). The
  generated manifest `swift build`s and `swift test`s clean out of the box.
  Shellcheck CI now covers `scripts/**.sh`.

- **`concise-comments-and-commits.md`** (core, cross-platform) — fires on all
  Swift/Kotlin/ObjC source. Comments default to none (why-not-what, no diff
  commentary or narration); commit messages get a short imperative subject and
  a body only when the why isn't visible in the diff. Targets the verbosity AI
  assistants produce that stops teammates reading either.

- **`apple-swiftui-mvvm.md` and `apple-testing-strategy.md` are checklists
  now.** Both load for every `.swift` file; their examples and reasoning moved
  to `swiftui-pro/references/mvvm-conventions.md` and
  `swift-testing-pro/references/test-strategy.md` (about 13 KB less context
  per Swift session).
- **`apple-testflight-deployment.md` no longer loads for `Info.plist`,
  `project.pbxproj`, `.xcconfig`, or `.entitlements` edits**, only for
  fastlane files, export options, and CI configs. Its sample workflow uses
  `macos-26` and an exact Xcode 27 pin (it used `macos-14` with Xcode 15.4,
  which can't build for the current SDK), and the build-number error code is
  corrected.
- **The shipped `.claude/settings.json` is narrower.** It no longer
  pre-approves `git commit`, `git push`, or every `gh` command; `gh` is limited
  to read verbs, and `swift` to `build`/`test`/`package` reads. A new `deny`
  list blocks force-pushes, `git reset --hard`, `gh repo delete`, and reading
  `.env`, `.p8`/`.p12` keys, and keystores. Existing installs keep their file.
- **The MCP server needs Node 22+** (Node 20 reached end of life in April 2026).

- **Claude Code rules are path-scoped again.** Claude Code scopes
  `.claude/rules/*.md` by a `paths:` list and ignores `globs:`, so every
  installed rule loaded in every session (about 50k tokens for an Apple
  install). Each rule now carries a `paths:` list matching its `globs:`
  (kept for Cursor and Kiro), and `validate-frontmatter.py` fails when the
  two drift. The TestFlight and Play beta rules no longer match every YAML
  file, only CI configs.

- **Accessibility rules — Bluetooth assistive tech + latest-practice refresh**
  across all three a11y rules. New coverage: Full Keyboard Access / Switch
  Control / braille-display discipline (SwiftUI `.focusable()` +
  `@AccessibilityFocusState`; UIKit `canBecomeFocused` +
  `accessibilityRespondsToUserInteraction`; Compose focus + visible indicators),
  audio/hearing (no sound-only cues, system captions), and App Store
  Accessibility Nutrition Label honesty (a VoiceOver claim = all common tasks
  work under VoiceOver). Verified-current API guidance: SwiftUI
  `AccessibilityNotification.Announcement` + priority, UIKit
  `UIAccessibilitySpeechAttributeAnnouncementPriority`, and Android 16's
  `announceForAccessibility` deprecation → `liveRegion` / `paneTitle` /
  `stateDescription` semantics (braille over Bluetooth HID is OS-level since
  Android 15 / TalkBack 15).

- **README — new "Building with AI agents (after install)" section.** The docs
  covered installing via an agent but not building with the bundle day-to-day;
  added guidance on naming rules when correcting the agent, invoking the
  deep-review skills explicitly, the Claude-only skills caveat for other agents,
  scoped sessions, and staying current via `upgrade`.
- **CLAUDE templates — richer "AI Rules and Skills" guidance.** All three
  starter templates now coach explicit skill invocation, rule-citation when the
  agent slips, and the upgrade pointer. Fixed the stale Android note claiming
  Android skills don't exist yet (they do — `android-compose-pro`,
  `android-coroutines-pro`).

### Fixed

- **Adopted apps keep `Package.resolved` under version control.** The
  installer's `.gitignore` block now ignores it only for a library (a root
  `Package.swift` with no Xcode project), as `apple-spm-package-conventions.md`
  says. Existing installs keep their old block; remove the line by hand.
- **Install no longer overwrites rule or skill files that are already there.**
  A file that differs from the bundle copy is kept and listed (use `--force` to
  replace it); an identical one is adopted into the manifest. Skills are copied
  file by file, so a re-install no longer nests `skills/x/x/` on Linux.
- **Mistyped flags fail instead of becoming the target.** `install.sh` and
  `scaffold-spm-package.sh` reject unknown options, a second positional, and a
  value flag with no value, with a clear message.
- **The MCP `install` tool auto-detects the platform** when none is given,
  like the shell install. It used to force `--platform both`, which put
  Android rules into iOS-only repos. Every `target_dir` must now be absolute,
  and tools pass an explicit verb (`install`, `upgrade`, `uninstall`).

- **Scaffolded packages follow the bundle's own rules.** Placeholders are
  named `<Module>Placeholder` (a type named like its module breaks
  module-qualified lookups), only `AppCore` is a product when there's an
  umbrella, and `AppCore` gets an `AppRootView` for the app's `@main`. The
  scaffold rejects duplicate module names, system-module names, and names
  ending in `Tests`, and its `makeTargets()` now matches the template's.
- **`install.sh audit` detects SwiftUI `App` and `UIApplicationDelegate`
  types again**, so `apple-no-scene-lifecycle` can fire. The check was looking
  for them only in Gradle files.
- **Package manifests with an example app are audited as packages.** A root
  `Package.swift` whose only Xcode projects sit in `Example/`, `Demo/`, or
  `Samples/` no longer gets app-store findings.
- **`manifest-conventions.md`:** a library with no `type:` is automatic (the
  client decides, usually static), not dynamic; Swift 5 mode uses
  `enableUpcomingFeature("StrictConcurrency")`.

## [1.0.0] - 2026-06-11

### Added

- **`android-ai-best-practices.md`** — the `ai` category is now cross-platform.
  The Android counterpart to the Apple Foundation Models rule: on-device Gemini
  Nano via ML Kit GenAI / AICore vs cloud Gemini via Firebase AI Logic, never
  ship a raw model API key (App Check / backend proxy), two-level availability
  gating, streaming into Compose with placeholder-then-mutate, structural
  cancellation, interface + fake testability, consent + Data-safety hooks.
  Previously `--platform android --features ai` installed nothing.
- **`swiftdata-pro` skill** (persistence) — Paul Hudson's MIT
  [`swiftdata-agent-skill`](https://github.com/twostraws/swiftdata-agent-skill),
  bundled alongside `coredata-swift6-pro`: core model/context rules, safe
  `#Predicate` usage, CloudKit constraints, iOS 18+ indexing, iOS 26+ class
  inheritance.
- **`android-compose-pro` skill** (ui) — deep Compose review: recomposition
  stability + skippability (strong-skipping aware), side-effect audit
  (`LaunchedEffect` keys, `rememberUpdatedState`, `DisposableEffect` teardown),
  lazy-list performance (keys, `contentType`, `derivedStateOf`), state modeling.
- **`android-coroutines-pro` skill** (concurrency) — deep coroutines/Flow
  review: scope-to-lifecycle mapping, cooperative cancellation
  (`CancellationException` / `runCatching` traps), `launch` vs `async`
  exception propagation, supervisor boundaries, `stateIn`/`shareIn`
  configuration, `callbackFlow` teardown, coroutine testing (virtual time,
  Turbine). Android skill parity: 5 Android skills alongside 9 Apple.
- **Privacy-manifest / Data-safety guidance in the deployment rules** —
  `apple-testflight-deployment.md` gains a `PrivacyInfo.xcprivacy` section
  (required-reason APIs, collected-data types, tracking domains, third-party
  SDK manifests, ITMS-91053/91061 — the upload gate AI-generated code trips
  most often); `android-play-beta-deployment.md` gains the Play Data safety
  form discipline (SDK-sourced data, mismatch enforcement, AI-SDK triggers).

- **One-command installer (`install.sh`)** that copies the matching rules,
  skills, settings, `CLAUDE.md` template, and `.gitignore` entries into a
  target repo. Never overwrites an existing `CLAUDE.md`, `settings.json`, or
  agent file — prints what it skipped.
- **Platform auto-detection** — with no `--platform`, the installer sniffs the
  target dir (`Package.swift` / `*.xcodeproj` → apple; `build.gradle*` /
  `gradlew` → android; both → both; neither → both) and prints the matched
  signals. Explicit `--platform` always wins.
- **`--features` categories** with a `recommended` preset (the 9 day-one
  categories) and `all`. Composable CSV (`recommended,ai,spatial`).
- **`--apple-platforms` selector** — CSV of `ios,macos,tvos,watchos,visionos`
  (or `all`); default `ios,macos,tvos,watchos` (every Apple platform except
  visionOS, the lean default for typical app projects). Only the visionOS rule
  is sub-platform-specific today, so the selector stays in sync with the
  `spatial` feature category (naming `visionos` ⇔ installing the visionOS rule;
  `--features …,spatial` remains the equivalent older form). Recorded in the
  manifest (`apple_platforms_input` / `_resolved`) and inherited on `--upgrade`.
  A forward-looking framework for future platform-specific rules.
- **`--android-platforms` selector** — CSV of `phone,tablet,wear,tv,auto` (or
  `all`); default `phone,tablet`. The Android counterpart to `--apple-platforms`,
  but purely a forward-looking framework: **no Android rule is form-factor-specific
  today**, so it doesn't change what installs — it's validated, recorded in the
  manifest (`android_platforms_input` / `_resolved`), inherited on `--upgrade`,
  and surfaced in `--list`/`--json`. A Wear OS / Android TV / Auto rule would gate
  by these tokens.
- **Multi-agent installs (`--agents`)** — `claude` (default), `copilot`,
  `cursor`, `gemini`, `codex`, `kiro`, or `all`. Generates each agent's native
  file shape (`.github/copilot-instructions.md`, `.cursor/rules/*.mdc`,
  `GEMINI.md`, `AGENTS.md`, `.kiro/steering/*.md`) from the same rule source.
  Skills stay Claude-only.
- **Kiro support (`--agents kiro`)** — writes per-rule
  [steering files](https://kiro.dev/docs/steering/) to `.kiro/steering/<name>.md`,
  rewriting each rule's `globs` frontmatter into Kiro's
  `inclusion: fileMatch` + `fileMatchPattern` (single glob, or an inline array
  for multi-pattern rules) so a rule only enters Kiro's context when a matching
  file is open. Generation is shared between install and the upgrade overlay, so
  the 3-way diff round-trips; `--upgrade`/`--uninstall` track it like any other
  agent file.
- **`--upgrade`** — a per-file 3-way diff (installed hash vs. current disk vs.
  bundle) that classifies every tracked file as up-to-date / safe-update /
  locally-edited / conflict / orphan / addition / rename, plus the same diff
  for MCP entries. Plan-only by default.
- **`--upgrade --apply`** with `--force-conflicts` (overwrite locally-edited
  files), `--prune` (delete orphans + out-of-scope), and `--migrate-manifest`
  (bring a v1 manifest forward). Surfaces a GitHub compare URL when the bundle
  commit differs.
- **`--uninstall`** with `--force-conflicts`, `--purge` (also remove
  `CLAUDE.md`/`settings.json`), and `--keep-mcps`. Strips the `.gitignore`
  block and the manifest; preserves non-`mcpServers` keys in
  `settings.local.json`.
- **`--with-mcps` + `--list-mcps`** — five curated MCP-server recipes
  (XcodeBuildMCP, Xcode-native, android-mcp-server, Firebase, Sentry) merged
  into `.claude/settings.local.json` with config hashing.
- **`--dry-run`** and **`--list` / `--list --json`** (machine-readable catalog
  consumed by the MCP server).
- **Guided setup (`-i` / `--interactive`)** — a prompt-driven flow that detects
  whether you're creating a new project, adopting into an existing repo, or
  updating an existing install, then walks through platform / Apple-language /
  features / agents / MCP recipes with sensible defaults. Reads answers at a TTY
  or from piped stdin (Enter accepts each default), prints a plan, and confirms
  before writing.
- **`--new`** — create the target directory (and parents) and `git init` a fresh
  repo before installing, for green-field projects. Light scaffolding only — it
  doesn't generate an Xcode/Gradle project.
- **Managed-target guard** — running plain `install` over a directory that
  already has an AppBootstrapAI install now refuses with guidance to use
  `--upgrade` (which preserves the manifest baseline), instead of silently
  resetting it. Pass **`--force`** to deliberately re-install over a managed
  target.
- **`AGENTS.md`** at the repo root — a terse, machine-first guide for AI agents
  *operating* AppBootstrapAI (the recommend → preview → run workflow, the verb
  table, the create/adopt/upgrade situations, and the guardrails). Distinct from
  the `AGENTS.md` the installer writes into target repos.
- **`recommend` command** — `install.sh recommend <dir> [--json]` analyzes a
  directory (read-only) and prints the exact create / adopt / upgrade command to
  run, with rationale. Detects managed-state (manifest present → upgrade),
  platform + signals, Apple-language (`.m`/`.mm`/`.h` scan), and framework usage
  → feature categories (`import FoundationModels` → `ai`; Core Data / SwiftData
  → `persistence`; Room → `persistence`; R8/ProGuard → `shrinking`; XML layouts
  / Fragments → `migration`; fastlane / CI → `deployment`). `--json` emits a
  machine-readable object with a ready-to-exec `command` array — built so an AI
  agent gets the right action in one call instead of grepping the tree.
- **Subcommand verbs** — `install.sh` now accepts a leading command verb
  (`install` / `recommend` / `upgrade` / `uninstall` / `list` / `list-mcps` /
  `setup` / `help`), so `install.sh upgrade .` reads correctly instead of
  `install.sh . --upgrade`. Backward-compatible: every verb has a `--flag`
  alias and the bare `install` verb is optional, so existing scripts, the MCP
  server, and CI keep working unchanged. The file name stays `install.sh`.
- **Manifest v2** at `.claude/.appbootstrap-manifest.json` — per-file SHA-256
  hashes, `bundle_commit`, full selection, and `mcps_installed`. Powers the
  upgrade/uninstall flows.
- **`RENAMES.md`** — rule + skill-directory rename tracking honored by
  `--upgrade` so renames show as a single row, not delete + add.
- **Apple rules** — Swift 6.4 strict concurrency, SwiftUI MVVM, Foundation
  Models, accessibility, Objective-C + ObjC accessibility, SPM conventions,
  DocC strategy, testing strategy, localization, **linting** (SwiftLint +
  formatter), **logging** (os.Logger / privacy markers / levels), **visionOS**
  (spatial), and **TestFlight deployment**.
- **Android rules** — coroutines, Compose, Gradle conventions, project rules,
  accessibility, KDoc strategy, testing strategy, localization, **linting**
  (ktlint + detekt + Android Lint), **logging** (Timber / release-stripping /
  crash-reporter integration), and **Play beta deployment**.
- **Cross-platform** — project documentation rule (README/CHANGELOG/ADR).
- **Skills (Apple/Swift)** — `swift-concurrency-pro`, `swift-docc-pro`,
  `swift-error-handling-pro`, `swift-logging-pro`, `swift-package-pro`,
  `swift-testing-pro`, `swiftui-pro`, `coredata-swift6-pro`. **(Android)** —
  `android-gradle-architecture-pro`, `r8-shrink-pro`,
  `xml-to-compose-migration-pro`.
- **`linting`** feature category — in the `recommended` default set (10
  categories). **`spatial`** (visionOS) and **`deployment`** (TestFlight + Play
  beta) feature categories — opt-in, not in `recommended`.
- **MCP server** (`mcp-server/`) wrapping `install.sh` as nine typed tools:
  `recommend_setup` (analyze a dir → suggested command, the agent's entry point),
  `list_categories`, `list_rules`, `list_skills`, `preview_install`, `install`,
  `preview_upgrade`, `preview_uninstall`, `uninstall`. Reads its category set
  live from `install.sh --list --json`.
- **Templates** — `Package.template.swift` (with a `makeTargets()` helper) and
  three starter `CLAUDE.md` templates (apple / android / cross-platform).
- **Git-workflow guardrails** in `CLAUDE.md` and every template: never commit,
  push, amend, or run destructive git commands without explicit instruction.
- **CI** — `shellcheck`; `frontmatter` (rule/skill validation); a cross-OS
  (Ubuntu + macOS) `install-smoke-test` with 250+ assertions; an `mcp-server`
  workflow (`tsc` build + startup smoke); and a `python` workflow
  (`ruff check --select F` + `py_compile`) covering `lib/*.py` and
  `.github/scripts`.

### Changed

- **Apple rules refreshed for Xcode 27 / Swift 6.4.** Version labels bumped from
  Swift 6.2 → 6.4 (language mode stays `.v6` — unchanged since 6.0); testing
  strategy gains `swift test --repeat-until` flaky-test hunting + the new
  XCTest ↔ Swift Testing interop warning; TestFlight deployment notes the
  Apple-silicon-only toolchain (macOS Tahoe 26.4), the `x86_64`/`ARCHS_STANDARD`
  drop at deployment target ≥ 27, and the `ld64`/`-ld_classic` removal (also a
  new SPM `unsafeFlags` caveat). Skill feature-attribution stays at 6.2 (those
  features shipped in 6.2).
- **Foundation Models modernized for the 2026 SDKs** — the rule now covers the
  pluggable-model surface (`LanguageModel` protocol; `SystemLanguageModel`
  on-device; `PrivateCloudComputeLanguageModel`; `LanguageModelExecutor` to
  bridge external providers like Claude/Gemini), image input
  (`Attachment` / `ImageAttachmentContent` / `ImageReference`), the Foundation
  Models Instrument, and `LanguageModelError`. New symbols are flagged **Beta /
  verify against the iOS 27 SDK**; the stable lifecycle/streaming patterns are
  unchanged.
- **README Apple MCP tooling refreshed** for Xcode 27's native Xcode MCP server
  (debug tools, Preview Snapshot, simulator control), `lldb-mcp`, and **agent
  plug-ins** (skills / MCP / ACP / slash commands) — superseding the Xcode 26.3
  `mcpbridge` framing.
- **Localization rule** notes Xcode 27's `NSLocalizedString`-from-headers
  extraction, the "do not translate" / `translate="no"` convention, and String
  Catalog "Generate Translations" (draft-only; review before shipping).
- **`install.sh` modularized** from a ~2,800-line monolith into a ~460-line CLI
  dispatcher plus `lib/` modules: six sourced bash files
  (`predicates.sh`, `detect_platform.sh`, `list_modes.sh`, `install_mode.sh`,
  `install_mcps.sh`, `upgrade_mode.sh`), four Python modules (`upgrade.py`,
  `uninstall.py`, `mcp_merge.py`, `inherit_selection.py`), and `help.txt`.
- **MCP server reads the category set live** from `install.sh --list --json`
  instead of a hand-maintained array, eliminating a drift class.
- **README + GitHub About** reframed to lead with multi-agent support and the
  full Apple/Android coverage including visionOS and deployment.

### Fixed

- CI path filters now cover `lib/**` — the modularization had moved most of the
  installer logic out of the watched paths, silently narrowing shellcheck and
  smoke-test coverage.
- Shellcheck `SC2034` false positives on cross-file globals (the linter doesn't
  follow `source=` directives) silenced with targeted, documented disables.
- Stray `f`-prefix on a placeholder-less string in `lib/upgrade.py`.
