---
description: Enforce Jetpack Compose patterns — state hoisting, side effects, Modifier ordering, stability, lifecycle-aware collection, and recomposition discipline
globs: "**/*.{kt,kts}"
---

# Jetpack Compose Best Practices

Compose recomposes — a lot. Most performance and correctness bugs in Compose come from misunderstanding *when* something runs. The rules below pin where state belongs, when side effects fire, and how to keep recomposition cheap.

## State Hoisting

- **Composables stay stateless when possible.** Hoist state to the lowest common ancestor that needs it; pass `value` down and `onValueChange` up.
- **Use `remember { ... }` for in-composition state** that doesn't need to survive config changes (UI flags, scroll offsets, animation values).
- **Use `rememberSaveable { ... }` for state that must survive config changes** (form input, expanded/collapsed flags, selected tabs).
- **Don't put business state inside `remember`.** Business state belongs in a `ViewModel` or repository — it must outlive the composable.

## Side Effects

Compose's body runs many times per second. Anything with a side effect goes inside one of these:

- **`LaunchedEffect(key1, key2, ...)`** — runs a coroutine when keys change. Use for one-shot suspend work tied to composition.
- **`DisposableEffect(key1, ...)`** — for setup that needs paired teardown (registering listeners, observers, broadcast receivers).
- **`SideEffect { }`** — runs after every successful composition. Use to publish state to non-Compose code (analytics, logging frameworks expecting "screen visible" callbacks).
- **`rememberCoroutineScope()`** — gives you a scope that lives as long as the composable. Use for fire-and-forget from event handlers (button clicks).
- **`produceState(initial, key) { ... }`** — converts a non-Compose async source into Compose-readable state.

**Rule:** never start a coroutine, register a callback, or publish state from inside the composable body directly. If you find yourself writing `coroutineScope.launch` outside one of the patterns above, you have a bug.

## Recomposition & Stability

- **Mark data classes that flow into composables `@Stable` or `@Immutable`** so Compose can skip recomposition when their contents haven't changed by reference equality.
  - `@Immutable` — strongest guarantee: no public mutable state, no observable state, equality is structural.
  - `@Stable` — public state may change, but changes are notified to Compose.
- **`List<T>` from `kotlin.collections` is *not* stable** by default. Either use `ImmutableList` from `kotlinx.collections.immutable`, or annotate the holder type as `@Immutable`.
- **Hoist lambdas via `remember`** when they capture state and are passed to children — otherwise a new lambda is allocated per recomposition and the child sees a "changed" parameter.
  - Better still: use method references (`onClick = viewModel::refresh`) where possible.
- **Don't read state you don't need.** Reading `viewModel.state.value` in a composable subscribes the *whole* composable to that state. Read narrower types or use `derivedStateOf`.

## `derivedStateOf`

- **Wrap computations that depend on observed state** when you only want recomposition to fire when the *result* changes:

  ```kotlin
  val showScrollToTop by remember {
      derivedStateOf { listState.firstVisibleItemIndex > 5 }
  }
  ```

  Without `derivedStateOf`, the parent recomposes every time `firstVisibleItemIndex` changes (every scroll event). With it, recomposition only fires when the boolean flips.

## Modifier Order Matters

`Modifier` chains apply in *order*. The order is meaningful — it changes the visual result.

- **`.padding().background()`** — padding *outside* the background.
- **`.background().padding()`** — background fills, padding inside the colored area.
- **General rule:** layout modifiers (`size`, `padding`, `offset`) → drawing modifiers (`background`, `border`, `clip`) → input modifiers (`clickable`, `pointerInput`).
- **`.fillMaxSize()` before `.padding()`** if you want the padding inside the filled area; reverse if you want the parent's space minus padding to be filled.

## Lifecycle-Aware Collection

- **Always use `collectAsStateWithLifecycle()`** to read a `Flow` or `StateFlow` in a composable. Raw `collectAsState()` keeps collecting in the background — wastes CPU/network on screens the user can't see.

  ```kotlin
  val state by viewModel.state.collectAsStateWithLifecycle()
  ```

- The lifecycle-aware version is in `androidx.lifecycle:lifecycle-runtime-compose` — add it explicitly to your dependencies.

## Lists and `LazyColumn`/`LazyRow`

- **Provide stable `key` lambdas** so Compose can match items across recompositions instead of recomposing the whole list:

  ```kotlin
  LazyColumn {
      items(items, key = { it.id }) { item ->
          ItemRow(item)
      }
  }
  ```

- **Without keys, every insertion / deletion re-layouts everything below.** With keys, Compose moves the existing nodes.
- **Don't put expensive logic in the item lambda body** — extract sub-composables that take the minimum data they need so they can be skipped individually.

## Common Pitfalls

- **Mutating state during composition.** Forbidden — wrap in a `LaunchedEffect` or event handler. Compose's exception will tell you, but it's preventable.
- **Calling `viewModel.something()` from the composable body** without a side-effect wrapper — runs every recomposition.
- **Passing inline lambdas that capture state** to many children — cheap to write, expensive to render. Hoist with `remember`.
- **Reading too much state** in a top-level composable so child changes recompose the whole tree — push state reads down.
- **Using `MutableState` to hold business state** instead of a ViewModel — the state dies on rotation.
- **`collectAsState()` instead of `collectAsStateWithLifecycle()`** — pauses-on-background is what you want every time.
- **`remember { mutableStateOf(...) }` inside a `LazyListScope.items` block** — the lambda is *not* a `@Composable` scope; remember the state at the parent level.

## Patterns to Follow

```kotlin
// Stateless, hoisted Composable
@Composable
fun CounterRow(
    count: Int,
    onIncrement: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .padding(16.dp)
            .clickable(onClick = onIncrement)
            .semantics(mergeDescendants = true) { },
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(stringResource(R.string.count_label, count))
    }
}

// Stateful wrapper that reads from a ViewModel and forwards to the stateless one
@Composable
fun CounterScreen(viewModel: CounterViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    CounterRow(
        count = state.count,
        onIncrement = viewModel::increment
    )
}

// derivedStateOf — recompose only when the predicate flips, not on every scroll tick
@Composable
fun ScrollToTopButton(listState: LazyListState) {
    val showButton by remember(listState) {
        derivedStateOf { listState.firstVisibleItemIndex > 5 }
    }
    AnimatedVisibility(visible = showButton) { /* ... */ }
}

// LaunchedEffect — one-shot suspend work tied to composition lifecycle
@Composable
fun ToastEffect(events: SharedFlow<UiEvent>) {
    val context = LocalContext.current
    LaunchedEffect(events) {
        events.collect { event ->
            Toast.makeText(context, event.message, Toast.LENGTH_SHORT).show()
        }
    }
}
```
