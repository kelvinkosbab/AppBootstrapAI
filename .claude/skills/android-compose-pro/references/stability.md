# Recomposition stability and skippability

A Composable skips recomposition when Compose can prove its parameters haven't changed. Most "Compose is slow" reports are skippability failures: a parent invalidates, children's parameters look changed (by reference or by being unprovable), the whole subtree re-executes.

## Strong skipping changes the baseline

Compose compilers paired with Kotlin 2.0.20+ enable **strong skipping mode by default**: composables with *unstable* parameters are still skippable (unstable params compared by instance equality), and lambdas are automatically remembered. Before recommending annotations, establish which compiler the project uses:

- **Strong skipping ON (modern default)** — most historical advice ("annotate everything `@Immutable`", "wrap every lambda in `remember`") is obsolete. Flag *leftover* cargo-cult annotations and manual lambda-remembering that no longer pay rent.
- **Strong skipping OFF (older toolchains)** — the classic rules apply in full; unstable parameters genuinely defeat skipping.

Instance-equality on unstable params has a sharp edge even with strong skipping: code that *recreates* an equal-but-not-same object each frame (`items.filter { ... }` in the body, `copy()` chains) still defeats skipping. The fix is the same either way — stop allocating per-composition.

## Diagnosing, not guessing

- **Compiler reports**: enable the Compose compiler metrics/reports Gradle options and read the `-classes.txt` / `-composables.txt` output — it states per-composable skippability and per-parameter stability. Cite these over intuition.
- **Layout Inspector recomposition counts**: the runtime ground truth. A composable recomposing hundreds of times during one scroll is the finding; the parameter analysis explains it.
- A composable that's restartable-but-not-skippable and sits in a hot path (list item, animated container) is a real finding. The same status on a screen root that recomposes twice per navigation is noise — say so.

## Stability contracts

- **`@Immutable`** — promise: no observable mutation ever. Violating it (a `var` mutated post-construction) causes *missed* recompositions — a correctness bug worse than the perf problem it was meant to fix. Verify the promise before approving the annotation.
- **`@Stable`** — promise: mutations notify composition (e.g., backed by `mutableStateOf`). Right for state-holder classes.
- **Collections**: `List`/`Set`/`Map` interfaces are unstable (a `MutableList` may hide behind them). Options, in preference order: strong skipping handles it; `kotlinx.collections.immutable` (`ImmutableList`); a `@Immutable`-annotated wrapper class. Converting with `.toImmutableList()` per composition re-allocates — do it in the ViewModel, once.
- **Cross-module types** are unstable to the consumer module unless annotated or covered by a stability configuration file (`compose.stabilityConfigurationFile`) — the right tool for types you don't own (e.g., `java.time.LocalDate`).

## Lambda hygiene

```kotlin
// Method references survive recomposition with stable identity:
ItemRow(onClick = viewModel::onItemClicked)

// Capturing lambda: fine under strong skipping (auto-remembered) IF captures are stable.
// Capturing an unstable object forces re-allocation — restructure to capture an id:
ItemRow(onClick = { viewModel.onItemClicked(item.id) })
```

Flag: lambdas capturing whole unstable objects when an id/value would do; `remember { { ... } }` noise under strong skipping; event handlers allocated in loops without keying.

## Per-composition allocation smells

- `items.filter { }` / `.sortedBy { }` / `String.format` in a composable body → hoist to the ViewModel or wrap in `remember(items)`.
- Reading a whole `state` object where one field would do — pass narrow parameters so unrelated field changes don't invalidate the child.
- `derivedStateOf` for values that change more often than the UI cares (`scrollState.firstVisibleItemIndex > 0`); missing it means per-pixel recomposition. Conversely, `derivedStateOf` wrapping a cheap pure mapping of its only input is overhead — flag both directions.
