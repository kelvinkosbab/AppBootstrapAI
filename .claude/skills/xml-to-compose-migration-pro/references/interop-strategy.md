# Interop Strategy: Incremental Migration

The default migration strategy is **incremental** — one screen at a time, hybrid pages possible, big-bang rewrite is rarely the right call. `ComposeView` and `AndroidView` make this practical.

## Pick a migration boundary

For each screen, pick *one* boundary:

| Boundary | When to pick it | Pros | Cons |
|----------|-----------------|------|------|
| **Screen-level** (whole Fragment → Composable) | Default; most migrations | Clean break, full Compose ergonomics | Larger PRs |
| **Widget-level** (`ComposeView` inside an XML layout) | Specific widget (e.g., a chart) is easier to write in Compose | Tiny PR | Hybrid lifecycle pain |
| **Host-level** (`AndroidView` inside a Composable) | Existing custom `View` is hard to rewrite (MapView, WebView, third-party SDK) | Reuses tested view | One-way state flow |

**Default to screen-level.** Hybrid migrations create lifecycle complexity (View lifecycle and Compose lifecycle don't perfectly align), state-management duplication, and theme-discrepancy bugs.

## Order of migration

A reasonable order for a Compose-curious team:

1. **Leaf screens first** — settings, profile, "about" pages. Low traffic, low risk, builds team experience.
2. **Lists with simple items second** — feed-style screens where `LazyColumn` is a clean win over `RecyclerView`.
3. **Tab/main screens later** — once the team has migrated 3–5 screens, the patterns are clear.
4. **Complex screens (camera, charts, maps) last** — these often need `AndroidView` interop anyway; saving them lets the team build up Compose skill.

Don't migrate the *first* screen of a Compose journey. Start somewhere with low blast radius.

## `ComposeView` inside an XML layout

Use when you want to author a *single widget* in Compose inside an otherwise-XML screen:

```xml
<!-- res/layout/fragment_home.xml -->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical">

    <TextView ... />

    <androidx.compose.ui.platform.ComposeView
        android:id="@+id/compose_chart"
        android:layout_width="match_parent"
        android:layout_height="wrap_content" />

    <Button ... />
</LinearLayout>
```

```kotlin
class HomeFragment : Fragment() {
    private val viewModel: HomeViewModel by viewModels()

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val composeView = view.findViewById<ComposeView>(R.id.compose_chart)
        composeView.setViewCompositionStrategy(
            ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed
        )
        composeView.setContent {
            AppTheme {
                val state by viewModel.chartState.collectAsStateWithLifecycle()
                ChartCard(data = state.dataPoints)
            }
        }
    }
}
```

- **Always set a `ViewCompositionStrategy`** — `DisposeOnViewTreeLifecycleDestroyed` is the modern default. Without it, you can leak the Composition past the View's lifecycle.
- **`AppTheme { ... }` wraps every `setContent { }`** — `MaterialTheme` doesn't inherit from the XML theme, so the Composition has no design tokens unless you explicitly wrap.
- **State flows in via `collectAsStateWithLifecycle()`** — same as full Compose screens.

## `AndroidView` inside a Composable

Use when an existing `View` is hard to rewrite — third-party SDK views (Google Maps, video players), large custom views you don't want to touch yet:

```kotlin
@Composable
fun WebViewScreen(url: String, modifier: Modifier = Modifier) {
    AndroidView(
        modifier = modifier.fillMaxSize(),
        factory = { context ->
            WebView(context).apply {
                webViewClient = WebViewClient()
                settings.javaScriptEnabled = true
            }
        },
        update = { webView ->
            // Re-runs every recomposition the URL changes
            if (webView.url != url) {
                webView.loadUrl(url)
            }
        }
    )
}
```

- **`factory`** runs once when the View enters the composition.
- **`update`** runs on every recomposition that the read state changes — keep it cheap and idempotent.
- **State flows one-way** Compose → View. If the View needs to push state *back*, expose a callback parameter to `AndroidView` and invoke it from a View listener.
- **`AndroidView` is for *foreign* views.** Don't use it to wrap a regular Android `TextView` just because you don't feel like writing `Text(...)`. The whole point is to bridge to things Compose can't replace yet.

## What lives where during migration

During a multi-month migration, expect:

- **`:app/src/main/res/layout/`** — shrinking. Delete files only after the corresponding screen is migrated *and* QA'd.
- **`:feature:*/src/main/kotlin/`** — growing. Add new `*Screen.kt` Composables alongside the old `*Fragment.kt` until cutover.
- **Navigation** — both `nav_graph.xml` and `NavHost` may exist in parallel during a major migration. Aim for one source of truth per *flow*.
- **`activity_main.xml`** — likely becomes a single `<ComposeView>` containing the `NavHost`. The very last XML to delete.

## When NOT to migrate

- **Stable XML screen with no planned work** — migration carries risk for no benefit if the screen isn't changing anyway. Prioritize screens that need work *anyway*.
- **Third-party SDKs that ship Views** — keep them in `AndroidView` until the SDK ships Compose-native APIs. Don't reimplement them.
- **Performance-critical custom Views with optimized `onDraw`** — Compose's rendering model differs. Profile before assuming Compose is faster for an aggressively-optimized View.

## Migration metrics worth tracking

For a long-running migration, track these in a dashboard or even a comment in `CHANGELOG.md`:

- **% of screens** in Compose (count by Activity / Fragment / Compose nav destination)
- **% of `res/layout/*.xml` files** remaining (delete files, watch the count drop)
- **Hybrid screens** (`ComposeView` in XML or `AndroidView` in Compose) — these are technical debt to retire
- **`@AndroidEntryPoint` Fragments** vs `@Composable` screens — Hilt entry points become a different mechanism in pure Compose

The goal is zero of the first two when migration completes; some of the third is expected long-term (third-party SDKs).

## Common pitfalls

- **Forgetting `ViewCompositionStrategy`** — leaks. Always set `DisposeOnViewTreeLifecycleDestroyed`.
- **Not wrapping `setContent { }` in `AppTheme { }`** — your screen has no `MaterialTheme`. Buttons render with default M3 colors instead of brand.
- **Round-tripping state through `AndroidView`** — leads to update loops. State flows from Compose to View; events flow back via callbacks, not via observing the View.
- **Migrating navigation and screen content in the same PR** — too much surface change at once. Migrate screen content first (keep XML nav), then swap nav graph.
- **Deleting the XML in the same PR as the Composable lands** — no rollback. Land the Composable behind a feature flag, gather QA signal, delete the XML in a follow-up.
- **Two themes drift** — XML `styles.xml` and Compose `MaterialTheme` are independent. Either keep them in sync via tokens or migrate themes fully before migrating screens.
