# State modeling and hoisting

Where state lives determines what survives, what recomposes, and what's testable. Review state placement before anything else — most downstream findings trace back here.

## The placement ladder

From shortest-lived to longest-lived; state belongs at the *lowest* rung that satisfies its survival requirement:

1. **`remember { mutableStateOf(...) }`** — survives recomposition only. Pure UI ephemera: is-pressed, animation targets, text-field focus shims.
2. **`rememberSaveable`** — survives configuration change AND process death (via `SavedStateHandle` bundle). Form input, selected tab, expanded flags.
3. **ViewModel (`StateFlow<UiState>`)** — survives configuration change, owns business state, talks to the data layer.
4. **Repository / DataStore / Room** — survives everything; source of truth.

Flag state one rung too low (form input lost on rotation) or too high (a ripple animation in the ViewModel).

## Hoisting review

- **Stateless core + stateful wrapper.** A reviewable Composable takes `value` + `onValueChange` (or `state: UiState` + event callbacks); a thin wrapper connects it to a ViewModel. If a deep child reads a ViewModel directly via `hiltViewModel()`, previews and tests can't drive it — flag it.
- **Hoist to the lowest common ancestor**, not automatically to the screen root. Over-hoisting widens recomposition scope: a `TextField` whose every keystroke flows through the screen-level state holder recomposes the screen.
- **Events up, state down.** A child that mutates a `MutableState` passed from a parent (instead of invoking a callback) hides the write site. Flag `MutableState<T>` parameters; prefer `T` + `(T) -> Unit`.

## UiState shape

- **One observable state per screen** (`data class FeedUiState(...)` or a sealed hierarchy for mutually exclusive phases like `Loading/Loaded/Error`). Several independent `StateFlow`s that the UI must combine is a smell — combine in the ViewModel.
- **Sealed for phases, data class for facets.** `sealed interface` when states are exclusive; flat `data class` with defaults when independent facets vary (loading + list + banner). A sealed hierarchy where every branch duplicates the same five fields wants restructuring.
- **No framework types in UiState** — no `Context`, `View`, `NavController`, resources requiring a `Context`. Resolve strings via resource IDs or in the UI layer.

## Collection at the boundary

```kotlin
// The one blessed pattern:
val state by viewModel.state.collectAsStateWithLifecycle()
```

- `collectAsState()` (no lifecycle) keeps collecting in the background — flag it (the rule covers this too; the skill checks it actually happened).
- For `stateIn`-backed flows, check `SharingStarted.WhileSubscribed(5_000)` — the 5s grace keeps the upstream alive across rotation without burning it forever in the background.

## `rememberSaveable` correctness

- **Custom types need a `Saver`.** `rememberSaveable { mutableStateOf(MyClass(...)) }` crashes at parcel time unless `MyClass` is `Parcelable` or a `Saver` is supplied (`mapSaver` / `listSaver`).
- **Don't save what the ViewModel already owns** — double sources of truth diverge after process death.
- **Keys matter in lists**: `rememberSaveable` inside reorderable lazy items needs an input key tied to item identity, or restored state lands on the wrong row.

## Smells checklist

- `remember { mutableStateOf() }` holding anything fetched from a repository.
- A Composable with 5+ `remember` declarations that interact — that's a state holder class (`@Stable class FooState`) or ViewModel waiting to be extracted.
- `LocalContext.current` walked into business logic.
- Two-way `MutableState` parameters instead of value + callback.
- Mutating state during composition (not in a callback/effect) — correctness bug, flag always.
