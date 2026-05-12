# ViewModel Bridging

**Existing ViewModels carry over unchanged.** This is the single biggest reason XML-to-Compose migration is incremental rather than a rewrite: the state layer doesn't change.

## What stays the same

- `@HiltViewModel class FeedViewModel @Inject constructor(...) : ViewModel()`
- `viewModelScope.launch { ... }` for coroutines
- `SavedStateHandle` for process-death-safe state
- Repository / use-case dependencies via Hilt
- Public API surface — `fun refresh()`, `val state: StateFlow<FeedState>`, etc.

## What changes (small)

| Fragment-era | Compose-era |
|--------------|-------------|
| Expose `LiveData<UiState>` | Expose `StateFlow<UiState>` (preferred) — see migration note below |
| `oneShotEvent: LiveData<Event<NavigationCommand>>` | `SharedFlow<NavigationCommand>` |
| `Fragment.viewModels()` | `viewModel()` / `hiltViewModel()` |

`LiveData` still works in Compose via `observeAsState()`, but `StateFlow` + `collectAsStateWithLifecycle()` is the idiomatic pairing.

## Acquiring a ViewModel in a Composable

```kotlin
// Without Hilt:
@Composable
fun FeedScreen(viewModel: FeedViewModel = viewModel()) { ... }

// With Hilt (the common case):
@Composable
fun FeedScreen(viewModel: FeedViewModel = hiltViewModel()) { ... }
```

`hiltViewModel()` is from `androidx.hilt:hilt-navigation-compose`. It gives you a Hilt-injected ViewModel keyed to the nearest `NavBackStackEntry` — so navigating from `FeedScreen` to a detail screen and back gives you the *same* `FeedViewModel` instance, with its `StateFlow` state preserved.

## State observation

**`StateFlow` (recommended):**

```kotlin
val state by viewModel.state.collectAsStateWithLifecycle()
```

- Pauses collection when the screen is in the background.
- Always has a current value.
- `state` is the actual `UiState`, not a `State<UiState>` wrapper.

**`LiveData` (when migrating in place):**

```kotlin
val state by viewModel.state.observeAsState(initialValue = UiState.Loading)
```

- Active only while the composition is alive.
- Returns nullable type unless `initialValue` is provided.
- Slightly less efficient than `collectAsStateWithLifecycle`.

**`SharedFlow` for one-shot events:**

```kotlin
val context = LocalContext.current
LaunchedEffect(Unit) {
    viewModel.events.collect { event ->
        when (event) {
            is FeedEvent.ShowToast -> Toast.makeText(context, event.message, Toast.LENGTH_SHORT).show()
            is FeedEvent.NavigateTo -> navController.navigate(event.route)
        }
    }
}
```

`SharedFlow` (with `replay = 0` and `extraBufferCapacity = 1`) is the modern replacement for the `LiveData<Event<T>>` "single-event" pattern.

## Scoping ViewModels to a navigation graph

Sometimes two screens need to share state — e.g., a multi-step form across three Composables. Pin the ViewModel to a parent route:

```kotlin
NavHost(navController, startDestination = "form") {
    navigation(startDestination = "form/step1", route = "form") {
        composable("form/step1") { backStackEntry ->
            val parentEntry = remember(backStackEntry) {
                navController.getBackStackEntry("form")
            }
            val sharedVM: FormViewModel = hiltViewModel(parentEntry)
            FormStep1(viewModel = sharedVM)
        }
        composable("form/step2") { backStackEntry ->
            val parentEntry = remember(backStackEntry) {
                navController.getBackStackEntry("form")
            }
            val sharedVM: FormViewModel = hiltViewModel(parentEntry)
            FormStep2(viewModel = sharedVM)
        }
    }
}
```

Both `FormStep1` and `FormStep2` get the same `FormViewModel`. It's cleared when the user navigates out of the `"form"` nav graph.

## Activity-scoped ViewModels

For ViewModels that should outlive any single screen (auth state, app-wide preferences):

```kotlin
val activityViewModel: SessionViewModel = hiltViewModel(
    viewModelStoreOwner = LocalActivity.current as ViewModelStoreOwner
)
```

Or expose via Hilt's `@Singleton` and inject into other ViewModels rather than reaching for activity scope. Singletons are usually cleaner.

## Migrating from `LiveData` to `StateFlow`

For a ViewModel mid-migration:

```kotlin
// Before
class FeedViewModel(...) : ViewModel() {
    private val _state = MutableLiveData<FeedState>(FeedState.Loading)
    val state: LiveData<FeedState> = _state

    fun refresh() {
        viewModelScope.launch {
            _state.value = FeedState.Loading
            val result = repository.fetch()
            _state.value = result.fold(
                onSuccess = ::Loaded,
                onFailure = { FeedState.Error(it.message ?: "") }
            )
        }
    }
}

// After
class FeedViewModel(...) : ViewModel() {
    private val _state = MutableStateFlow<FeedState>(FeedState.Loading)
    val state: StateFlow<FeedState> = _state.asStateFlow()

    fun refresh() {
        viewModelScope.launch {
            _state.update { FeedState.Loading }
            val result = repository.fetch()
            _state.update {
                result.fold(
                    onSuccess = ::Loaded,
                    onFailure = { FeedState.Error(it.message ?: "") }
                )
            }
        }
    }
}
```

The `update { }` form is a compare-and-set that handles concurrent updates correctly. Direct `_state.value = ...` is fine for single-coroutine writes but `.update { }` is the safer default.

## `SavedStateHandle`

Unchanged across the migration. `SavedStateHandle` is process-death-safe whether you expose `LiveData` or `StateFlow`:

```kotlin
class FormViewModel @Inject constructor(
    private val savedStateHandle: SavedStateHandle
) : ViewModel() {

    val name: StateFlow<String> = savedStateHandle.getStateFlow("name", "")

    fun onNameChange(newName: String) {
        savedStateHandle["name"] = newName
    }
}
```

`getStateFlow(key, initialValue)` was added to `SavedStateHandle` specifically for the Compose era. Use it.

## Common pitfalls

- **Recreating the ViewModel by calling its constructor manually** — defeats the lifecycle scoping. Always go through `viewModel()` / `hiltViewModel()`.
- **`viewModel.state.value` read in a Composable** — reads once, doesn't subscribe to updates. Use `collectAsStateWithLifecycle()` or `observeAsState()`.
- **`collectAsState()` instead of `collectAsStateWithLifecycle()`** — the former doesn't pause in background. Always use the lifecycle-aware version.
- **Same ViewModel used by two unrelated Composables that should each have their own instance** — happens when both call `hiltViewModel()` at the same nav-graph scope. Pull the second composable into its own nav destination, or pass the VM explicitly so the parameter source is clear.
- **`hiltViewModel<MyViewModel>()` without the `hilt-navigation-compose` artifact** — won't compile. Add `androidx.hilt:hilt-navigation-compose` to dependencies.
- **Holding a reference to a Composable in the ViewModel** — never. The ViewModel publishes state; the View observes. No back-channel.
