---
name: xml-to-compose-migration-pro
description: Reviews and assists migration from XML layouts + Fragments to Jetpack Compose. Covers incremental interop (AndroidView / ComposeView), layout translation (ConstraintLayout / LinearLayout / FrameLayout → Modifier), RecyclerView → LazyColumn with keys, Fragment → Composable, Navigation Component → Navigation-Compose, ViewModel bridging, and XML themes → MaterialTheme.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
  grounded_in: "Android Developers Compose migration guide (https://developer.android.com/develop/ui/compose/migrate), Android Developers Compose docs"
---

Review and assist the migration from XML-based Android UI (Fragments + layouts + RecyclerViews) to Jetpack Compose. Migration is **incremental** by default — `ComposeView` / `AndroidView` make it possible to ship a hybrid screen-by-screen without a big-bang rewrite. Report only genuine migration issues; don't nitpick the existing XML where it doesn't need to change.

Review process:

1. Frame the migration scope using `references/interop-strategy.md` — incremental vs all-at-once, where to put interop boundaries.
2. Translate layouts using `references/layout-migration.md` — `LinearLayout` / `ConstraintLayout` / `FrameLayout` / `RelativeLayout` to Compose equivalents.
3. Translate RecyclerViews using `references/recyclerview-to-lazy.md` — including stable keys, item-content separation, and DiffUtil → automatic recomposition.
4. Translate Fragments using `references/fragment-to-composable.md` — lifecycle ownership, ViewBinding → parameters, animations.
5. Translate Navigation Component using `references/navigation-migration.md` — `NavGraph` XML → `NavHost` Kotlin DSL.
6. Bridge ViewModels using `references/viewmodel-bridge.md` — existing ViewModels stay; only the View layer changes.
7. Translate themes using `references/themes-styles.md` — `styles.xml` → `MaterialTheme(colorScheme, typography, shapes)`.

If doing a partial review, load only the relevant reference files.

## Core Instructions

- **Migrate incrementally.** A full XML-to-Compose rewrite of a non-trivial app is months of work; an incremental screen-by-screen migration ships value continuously. `ComposeView` in an XML layout (or `AndroidView` in a Composable) makes it possible.
- **Existing ViewModels stay.** Compose works with `ViewModel` + `StateFlow` + `LiveData` without changes. The migration is a View-layer concern, not a state-layer one.
- **Don't preserve XML idioms in Compose.** A `LinearLayout(orientation = horizontal)` becomes a `Row` — not a `Column` with `Modifier.fillMaxWidth().wrapContentHeight()`. A literal translation produces awkward Compose.
- **Test parity before deleting XML.** Snapshot tests, manual QA, or feature-flag the new screen alongside the old. Don't delete the XML in the same PR that introduces the Composable.
- **Use semantic `testTag` for tests, not preserved `android:id` values.** XML view IDs (`R.id.submit_button`) don't carry over; Compose uses `Modifier.testTag(...)` and `Modifier.semantics { contentDescription = ... }`.
- **`AndroidView { factory: ... update: ... }` is for one-way binding from Compose state to a `View`.** Don't try to round-trip — if state needs to flow back, lift it.

## Output Format

For migration reviews, organize findings by file. For each issue:

1. State the file and the XML element / Kotlin class.
2. Name the migration concern.
3. Show the XML/Fragment "before" and the Compose "after".

For migration *work* (rewriting a screen), make the changes directly and produce a final patch with the old XML deleted (or feature-flagged) and the new Composable + ViewModel wiring in place.

Example output:

### res/layout/fragment_settings.xml + SettingsFragment.kt

**Migrate to `SettingsScreen` Composable + Navigation-Compose route.**

```kotlin
// Before (SettingsFragment.kt) — Fragment + ViewBinding + RecyclerView
class SettingsFragment : Fragment() {
    private var _binding: FragmentSettingsBinding? = null
    private val binding get() = _binding!!
    private val viewModel: SettingsViewModel by viewModels()

    override fun onCreateView(...): View {
        _binding = FragmentSettingsBinding.inflate(inflater, container, false)
        binding.recyclerView.adapter = SettingsAdapter { onClick(it) }
        viewModel.items.observe(viewLifecycleOwner) { /* ... */ }
        return binding.root
    }
}

// After
@Composable
fun SettingsScreen(
    onItemClick: (SettingsItem) -> Unit,
    viewModel: SettingsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        items(state.items, key = { it.id }) { item ->
            SettingsRow(item = item, onClick = { onItemClick(item) })
        }
    }
}
```

**RecyclerView's `DiffUtil` is replaced by Compose's reference-equality-based recomposition.** Provide a stable `key` (e.g., `it.id`) so Compose can match items across emissions.

### Summary

1. **State exposure (medium):** `SettingsViewModel.items` is `LiveData` — migrate to `StateFlow` for `collectAsStateWithLifecycle()` consistency with other migrated screens.
2. **Theme (low):** New `SettingsScreen` references `MaterialTheme.colorScheme.surface`; ensure the host theme defines a non-default `colorScheme.surface`.

End of example.

## References

- `references/interop-strategy.md` — incremental vs all-at-once, `ComposeView` in an XML layout, `AndroidView` in a Composable, choosing screen-level vs widget-level migration boundaries.
- `references/layout-migration.md` — XML layouts → Compose equivalents: `LinearLayout` → `Row`/`Column`, `ConstraintLayout` → `Modifier` constraints + `ConstraintLayout` Composable, `FrameLayout` → `Box`, `ScrollView` → `Modifier.verticalScroll()`. Padding/margin/weight translation.
- `references/recyclerview-to-lazy.md` — `RecyclerView.Adapter` → `LazyColumn`/`LazyRow` with stable keys; `DiffUtil` → reference-equality recomposition; pagination via `paging-compose`.
- `references/fragment-to-composable.md` — `Fragment` lifecycle → Composable lifecycle, `ViewBinding` → Composable parameters, fragment transactions → navigation route changes, ActivityResultLauncher / system permissions in Compose.
- `references/navigation-migration.md` — XML `navigation/nav_graph.xml` → Kotlin `NavHost` + `composable("route")`, type-safe arguments, deep links, navigation results.
- `references/viewmodel-bridge.md` — existing `ViewModel`s carry over; `viewModel()` / `hiltViewModel()`, `LiveData` → `observeAsState()` (or migrate to `StateFlow` + `collectAsStateWithLifecycle()`), `SavedStateHandle` unchanged.
- `references/themes-styles.md` — `styles.xml` themes → `MaterialTheme(colorScheme, typography, shapes)`, dark/light handling, dynamic color (`dynamicColorScheme`), per-screen theme overrides.
