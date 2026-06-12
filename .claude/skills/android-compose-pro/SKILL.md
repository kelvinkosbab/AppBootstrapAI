---
name: android-compose-pro
description: Deep-reviews Jetpack Compose code for recomposition stability, side-effect correctness, lazy-list performance, and state modeling. Use when reading, writing, or reviewing non-trivial Compose UI — especially when chasing jank, runaway recomposition, or effect bugs.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
  grounded_in: "Android Developers Compose docs (performance/stability/side-effects), Android 'Now in Android' (https://github.com/android/nowinandroid)"
---

Review Jetpack Compose code for correctness and performance. This is the deep-review companion to the always-on `android-compose-best-practices.md` rule — the rule steers while writing; this skill audits what was written. Report only genuine problems; don't nitpick or invent issues.

Review process:

1. Check state modeling and hoisting using `references/state-modeling.md` — where state lives, who owns it, how it flows.
2. Check recomposition stability using `references/stability.md` — unstable parameters, lambda churn, skippability.
3. Audit every side effect using `references/side-effects.md` — keys, teardown, stale captures.
4. Check lazy-layout performance using `references/lazy-performance.md` — keys, contentType, scroll-driven state.
5. Spot-check semantics against the `android-accessibility-best-practices.md` rule (merged nodes, roles, contentDescription) — don't duplicate a full a11y audit here.

If doing a partial review, load only the relevant reference files.

## Core Instructions

- Target Kotlin 2.x with the Compose Compiler Gradle plugin; assume Material 3.
- **Recomposition is the lens.** Most Compose bugs and jank reduce to "this runs more often than the author thinks" — composition, effect launch, or lambda allocation. Trace the actual invalidation, don't guess.
- **Don't recommend `@Stable`/`@Immutable` as a reflex.** First check whether strong skipping (default under Kotlin 2.0.20+ Compose compilers) already covers the case; annotations are for genuine contracts, not cargo cult.
- **Side effects are guilty until proven keyed correctly.** Every `LaunchedEffect`/`DisposableEffect` gets the question: what restarts you, and is that the author's intent?
- **Business state never lives in `remember { }`.** ViewModel + `StateFlow` + `collectAsStateWithLifecycle()` is the boundary; flag exceptions.
- **Performance claims need a mechanism.** When flagging a perf issue, name the mechanism (per-frame recomposition, missing keys forcing re-layout, unstable lambda defeating skipping) — not just "this could be slow."

## Output Format

Organize findings by file. For each issue: state the file/line, name the violated principle, show a brief before/after. Skip files with no issues. End with a prioritized summary (correctness first, then performance, then style).

Example finding:

### FeedScreen.kt

**Line 41: `LaunchedEffect(Unit)` capturing `state.selectedId` — stale read after recomposition.**

```kotlin
// Before — selectedId is captured once; later changes are invisible to the effect
LaunchedEffect(Unit) { analytics.logOpen(state.selectedId) }

// After — key the effect on what it reads
LaunchedEffect(state.selectedId) { analytics.logOpen(state.selectedId) }
```

## References

- `references/state-modeling.md` — hoisting review, ViewModel boundary, UiState shapes, `rememberSaveable` + custom `Saver`, unidirectional data flow smells.
- `references/stability.md` — skippability diagnosis, strong skipping mode, `@Stable`/`@Immutable` contracts, unstable collections, lambda allocation, compiler reports.
- `references/side-effects.md` — `LaunchedEffect` keys, `rememberUpdatedState`, `DisposableEffect` teardown pairing, `SideEffect`, `produceState`, `snapshotFlow`, `rememberCoroutineScope`.
- `references/lazy-performance.md` — stable `key` + `contentType`, item-lambda hygiene, `derivedStateOf` for scroll-driven UI, nested-scroll traps, `animateItem`.
