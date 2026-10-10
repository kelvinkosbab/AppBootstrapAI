---
description: Android MVVM with unidirectional data flow — one StateFlow<UiState> per screen built with stateIn, events as ViewModel functions, one-off effects modeled as state, SavedStateHandle and type-safe nav args, stateful Route vs stateless Screen composables, and what stays out of a ViewModel
globs: "**/*.{kt,kts}"
---

# Android MVVM Architecture

Opt-in (`--features …,architecture`). This is the presentation-layer half of Android's recommended architecture: **UI → ViewModel → data layer**, with state flowing down and events flowing up (unidirectional data flow, UDF). It deepens the one-line "use MVVM" in [`android-project-rules.md`](./android-project-rules.md); the data layer the ViewModel talks to is covered in [`android-repository-pattern.md`](./android-repository-pattern.md). Coroutine and Flow mechanics live in [`android-coroutines-best-practices.md`](./android-coroutines-best-practices.md).

## When a Screen Gets a ViewModel

- **Yes** for any screen that loads data, holds state that must survive configuration changes, or coordinates async work — that's almost every navigation destination.
- **No** for leaf composables (rows, buttons, design-system components) — they take state and lambdas. A ViewModel per list row is a scoping bug.
- **One ViewModel per screen (navigation destination)**, scoped to its `NavBackStackEntry` via `hiltViewModel()`. Share across screens only through a navigation-graph-scoped ViewModel when the flow genuinely shares state (a multi-step checkout), never via a singleton.

## The ViewModel Shape

```kotlin
@HiltViewModel
class TaskListViewModel @Inject constructor(
    private val tasksRepository: TasksRepository,
    private val savedStateHandle: SavedStateHandle,
) : ViewModel() {

    private val filter = savedStateHandle.getStateFlow(KEY_FILTER, TaskFilter.All)

    val uiState: StateFlow<TaskListUiState> =
        combine(tasksRepository.observeTasks(), filter) { tasks, filter ->
            TaskListUiState.Success(tasks.filter(filter::matches), filter)
        }
            .catch<TaskListUiState> { emit(TaskListUiState.Error) }
            .stateIn(
                scope = viewModelScope,
                started = SharingStarted.WhileSubscribed(5_000),
                initialValue = TaskListUiState.Loading,
            )

    fun onFilterSelected(newFilter: TaskFilter) {
        savedStateHandle[KEY_FILTER] = newFilter
    }

    fun onTaskCompleted(id: TaskId) {
        viewModelScope.launch { tasksRepository.complete(id) }
    }
}
```

- **One `StateFlow<UiState>` per screen**, derived from repository flows with `combine` + `stateIn`. Prefer deriving state over imperatively pushing into a `MutableStateFlow` — derived state can't drift out of sync with its sources.
- **`SharingStarted.WhileSubscribed(5_000)`** — upstream collection stops when the UI is gone (backgrounded) but survives a configuration change.
- **Expose read-only types**: `StateFlow`, never `MutableStateFlow`. When imperative state is unavoidable, keep `private val _uiState = MutableStateFlow(...)` and mutate with `_uiState.update { }`.
- **Events are functions** named after what happened (`onTaskCompleted`, `onRetry`), not setters for UI fields.
- **Constructor-injected dependencies only** (repositories, use cases, dispatchers via qualifiers). No `Context`, `View`, `Activity`, `Resources`, or `NavController` in a ViewModel — they leak and make it untestable. Need a string? Emit a `@StringRes` id or a sealed message type and resolve it in the UI.

## Modeling UiState

- **Sealed interface** when the screen has mutually exclusive modes:

  ```kotlin
  sealed interface TaskListUiState {
      data object Loading : TaskListUiState
      data class Success(val tasks: List<Task>, val filter: TaskFilter) : TaskListUiState
      data object Error : TaskListUiState
  }
  ```

- **Single `@Immutable data class`** with fields when parts load independently (a profile header and a feed) — avoid a combinatorial sealed hierarchy.
- **UiState is UI-ready**: formatted, filtered, and mapped from domain models. Composables shouldn't re-sort or re-filter on every recomposition.
- **Stable types** (`@Immutable`, `ImmutableList`) so screens skip recomposition — see [`android-compose-best-practices.md`](./android-compose-best-practices.md).

## One-Off Effects (Navigation, Snackbars)

- **Prefer modeling them as state** (Android's official guidance): e.g. `val userMessage: UserMessage?` in UiState; the UI shows it, then calls `onUserMessageShown()` which clears it. State survives configuration changes and process death; a fire-and-forget event can be lost.
- **Navigation after an action** → a state flag (`isSaved = true`) the Route observes with `LaunchedEffect(uiState.isSaved) { if (it) onSaved() }`, where `onSaved` is a navigation lambda passed in from the nav graph.
- If you do use a `Channel` for effects, `receiveAsFlow()` and collect in `LaunchedEffect` with `repeatOnLifecycle` semantics — and accept it can drop events. Never a `SharedFlow(replay = 0)` collected only while started.

## Route vs Screen

```kotlin
@Composable
fun TaskListRoute(
    onTaskClick: (TaskId) -> Unit,
    viewModel: TaskListViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    TaskListScreen(
        uiState = uiState,
        onTaskClick = onTaskClick,
        onTaskCompleted = viewModel::onTaskCompleted,
        onFilterSelected = viewModel::onFilterSelected,
    )
}

@Composable
internal fun TaskListScreen(
    uiState: TaskListUiState,
    onTaskClick: (TaskId) -> Unit,
    onTaskCompleted: (TaskId) -> Unit,
    onFilterSelected: (TaskFilter) -> Unit,
    modifier: Modifier = Modifier,
) { /* stateless — previewable and testable without Hilt */ }
```

- **Route** (stateful): obtains the ViewModel, collects state with `collectAsStateWithLifecycle()`, wires navigation lambdas.
- **Screen** (stateless): takes `UiState` + lambdas; this is what `@Preview`s and Compose UI tests target.
- **Never pass the ViewModel down** into child composables.

## Saved State and Navigation Arguments

- **`SavedStateHandle`** for anything that must survive process death: user input, selected filter/tab, scroll anchors that matter. `getStateFlow(key, default)` makes it a flow source.
- **Navigation arguments** come from `SavedStateHandle` too — with type-safe Navigation Compose routes, `savedStateHandle.toRoute<TaskDetail>()`. Don't pass IDs through ViewModel setters after construction.
- **Pass IDs, not objects**, between screens; the destination's ViewModel loads from the repository (the single source of truth).

## Optional Domain Layer (Use Cases)

- Add a **use case** (`class GetVisibleTasksUseCase @Inject constructor(...) { operator fun invoke(...) }`) only when logic is **reused across ViewModels** or **combines several repositories** in a non-trivial way.
- Don't add pass-through use cases that only call one repository method — that's ceremony, not architecture.

## Testing

- ViewModels are plain classes: construct with **fake repositories** and a `MainDispatcherRule`; assert `uiState` emissions with Turbine. See [`android-testing-strategy.md`](./android-testing-strategy.md).
- `stateIn(WhileSubscribed)` only produces values while collected — tests must collect (`uiState.test { }` or a `backgroundScope.launch { uiState.collect {} }`), not read `.value` cold.
- Screen composables are tested with plain `UiState` values — no ViewModel, no Hilt.

## Common Pitfalls

- **Multiple public `MutableStateFlow`s** (`isLoading`, `items`, `error`) — inconsistent combinations reach the UI. One UiState.
- **`stateIn(SharingStarted.Eagerly)`** for screen state — keeps collecting forever after the UI leaves.
- **`Context`/`Resources`/`NavController` in a ViewModel** — leaks and untestable.
- **Loading data in `init {}` with an imperative `launch`** when a derived flow would do — and reloading on every configuration change when the Route calls a `load()` from `LaunchedEffect(Unit)`.
- **Business logic in composables** (filtering, sorting, validation) — it belongs in the ViewModel or domain layer.
- **ViewModel passed into child composables** — couples previews and tests to Hilt.
- **Fire-and-forget events lost** across configuration changes — model them as state.
- **Pass-through use cases** for every repository call.
