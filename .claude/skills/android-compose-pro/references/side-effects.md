# Side-effect audit

Effects are where Compose correctness bugs hide: an effect with the wrong key either restarts when it shouldn't (duplicate work, flicker, double analytics) or doesn't restart when it should (stale data, missed updates). Audit every effect against one question: **what restarts you, and is that intended?**

## `LaunchedEffect` keys

- **`LaunchedEffect(Unit)` (or `true`)** means "once per composition lifetime." Legitimate for one-shot entry work — but every value it reads is captured at launch. If the body reads state that changes, that's the stale-capture bug:

  ```kotlin
  // BUG: userId captured at first composition; navigating to another user re-uses the old one
  LaunchedEffect(Unit) { viewModel.load(userId) }

  // Fix: key on what you read — effect cancels + relaunches when userId changes
  LaunchedEffect(userId) { viewModel.load(userId) }
  ```

- **`rememberUpdatedState` is for the opposite intent**: a long-lived effect that must *not* restart, but needs to see the latest value:

  ```kotlin
  val currentOnTimeout by rememberUpdatedState(onTimeout)
  LaunchedEffect(Unit) {
      delay(SPLASH_MS)
      currentOnTimeout()      // latest lambda, effect never restarted
  }
  ```

- **Over-keying is also a bug**: keying on an unstable object that's recreated each composition restarts the effect every frame. Key on stable identity (an id), not the whole object.
- Relaunch cancels the previous block — verify the body tolerates cancellation mid-flight (no half-applied state).

## `DisposableEffect` — teardown pairing

- Every registration needs its exact unregistration in `onDispose`; flag asymmetries (listener added, never removed; different receiver instance removed).
- Key changes dispose-then-relaunch — confirm that ordering is safe for the resource (e.g., re-registering a lifecycle observer).
- An `onDispose {}` that's empty is a smell: either teardown is missing, or the code wanted `LaunchedEffect`.

## `SideEffect`

Runs after every successful recomposition — for publishing composition state to non-Compose code only (analytics screen-state, updating a third-party view's properties). Anything suspending, conditional, or expensive in `SideEffect` is misplaced.

## `produceState` and `snapshotFlow`

- `produceState(initial, key) { value = ... }` — bridge non-Compose async sources *into* state. Inside, `awaitDispose { }` mirrors `DisposableEffect` teardown for callback-based sources. Flag hand-rolled equivalents (`remember { mutableStateOf() }` + `LaunchedEffect` writing it) that drop teardown.
- `snapshotFlow { }` — bridge state *out* to a Flow. The block must read only snapshot state; emission is conflated. Classic use: `snapshotFlow { listState.firstVisibleItemIndex }` collected for analytics/paging triggers, properly debounced.

## `rememberCoroutineScope`

For launching from **event handlers** (`onClick`) — work tied to the composition's lifetime but triggered by the user. Misuses to flag:

- Launching in the composable body via this scope (runs every recomposition) — that's `LaunchedEffect`'s job.
- Long-lived business work launched here — dies when the user leaves the screen mid-flight; belongs in `viewModelScope`.

## Ordering and placement

- Effects run **after** the composition applies — code that assumes an effect ran before first frame is wrong.
- Navigation calls belong in event callbacks, not effects keyed on state (the "navigate in LaunchedEffect on a Boolean flag" pattern re-fires on config-change restore; if used, the flag must be consumed/reset in the same turn).
- One effect per concern. A 40-line `LaunchedEffect` doing three unrelated jobs with one key restarts all three when any key input changes — split it.
