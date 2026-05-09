---
description: Enforce structured concurrency, scope discipline, dispatcher choice, Flow/StateFlow/SharedFlow conventions, and cancellation safety in Kotlin coroutines
globs: "**/*.{kt,kts}"
---

# Kotlin Coroutines Best Practices

Structured concurrency is non-negotiable on Android: coroutines must live inside a scope tied to a real lifecycle. Leaked coroutines are the equivalent of leaked memory — they keep working long after the user has moved on, hold references that prevent garbage collection, and make tests flaky.

## Scope Discipline

- **Use the right scope for the lifetime of the work:**
  - `viewModelScope` for VM-tied work — auto-cancels in `onCleared()`.
  - `lifecycleScope` (or `LifecycleOwner.lifecycleScope`) for UI-tied work — auto-cancels in `onDestroy`.
  - `WorkManager` for background work that must survive process death.
- **Never use `GlobalScope`.** It outlives every screen and process boundary you care about. The only places it's defensible are `main()` in a CLI and tests that explicitly want unbounded work — in app code, treat it as a bug.
- **`runBlocking` is for `main()`, tests, and bridging into Java callers only.** Never in app code — it blocks the calling thread and breaks structured concurrency guarantees.
- **Don't store a `Job` reference and manually `cancel()` it** unless you have a concrete reason. Prefer scope-based lifecycle.

## Dispatchers

- **`Dispatchers.Main`** for UI work and view-state mutations. This is the default for `viewModelScope`/`lifecycleScope`.
- **`Dispatchers.IO`** for network, disk, and other blocking I/O. Use `withContext(Dispatchers.IO) { ... }` to switch in for the I/O call only — don't pin the whole function.
- **`Dispatchers.Default`** for CPU-bound work (parsing, image processing, large list transforms).
- **Don't reach for `Dispatchers.Main.immediate`** unless you've measured that it actually matters. The default `Main` is fine 99% of the time.
- **Inject dispatchers in production code:** `class Repository(private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO)` so tests can substitute `UnconfinedTestDispatcher`/`StandardTestDispatcher`.

## Cancellation

- **Cancellation is cooperative.** Suspend functions check it at suspension points; CPU-heavy non-suspending code does not, so call `ensureActive()` or `yield()` periodically inside long loops.
- **Never catch `CancellationException`.** Let it propagate so structured concurrency can do its job. If you need finally-style cleanup, use `try { ... } finally { ... }` — the cancellation will still propagate after the `finally` runs.
- **`withContext` is cancellation-safe;** if the parent cancels mid-call, the inner block is cancelled too.

## Flow, StateFlow, SharedFlow

- **`Flow<T>`** — cold stream of values. Each collector triggers the producer block. Use for one-shot async sequences (network responses, paginated data, cold queries).
- **`StateFlow<T>`** — hot, value-holding state. Always has a current value. Replaces `LiveData`. Use for view state.
- **`SharedFlow<T>`** — hot, one-shot events (snackbar messages, navigation events). Configure with `replay = 0` for fire-and-forget, `extraBufferCapacity` to avoid suspending emitters.
- **Don't expose `MutableStateFlow` / `MutableSharedFlow` from a ViewModel.** Expose the read-only base type (`val state: StateFlow<T> = _state.asStateFlow()`).

## Compose Collection

- **Always use `collectAsStateWithLifecycle()` in Compose,** never raw `collectAsState()`. The lifecycle-aware version pauses collection when the composable is in the background, so you don't burn CPU/network on a screen the user can't see.

  ```kotlin
  val state by viewModel.state.collectAsStateWithLifecycle()
  ```

- **Import from `androidx.lifecycle.compose.collectAsStateWithLifecycle`** — it's a separate dependency (`lifecycle-runtime-compose`).

## Exception Handling

- **`CoroutineExceptionHandler`** for top-level uncaught errors at the scope root (typically reporting to crash analytics).
- **`supervisorScope { ... }` / `SupervisorJob()`** when you want sibling coroutines to fail independently — one child failing does not cancel the others.
- **Don't wrap entire coroutines in `try { ... } catch (e: Exception) { }`.** Catch specific recoverable exceptions (`IOException`, `HttpException`) and let everything else bubble.
- **`runCatching`** is acceptable for boundary code that *must* return `Result<T>` (e.g., to display an error state) — but inside, only catch what you can handle.

## Common Pitfalls

- **`GlobalScope.launch { }`** in app code — replace with a proper scope.
- **`runBlocking { }`** in app code — refactor to `suspend` or use a proper scope.
- **Catching `CancellationException`** — drop the catch or rethrow.
- **Suspending while holding a non-coroutine lock** (`withLock { someSuspendCall() }` on a `kotlinx.coroutines.sync.Mutex` is fine; suspending under `synchronized { }` or a `ReentrantLock` is a deadlock waiting to happen).
- **Mutating `MutableStateFlow.value` from multiple coroutines without a strategy** — use `update { ... }` for compare-and-set semantics.
- **`Flow { ... }.flowOn(Dispatchers.IO).collect { /* mutate UI */ }`** in app code — `flowOn` only affects upstream; the collector still needs Main. Switch in the collector or use `.collect` from a `viewModelScope`.

## Patterns to Follow

```kotlin
// ViewModel — scope, expose read-only StateFlow, update via .update { }
@HiltViewModel
class FeedViewModel @Inject constructor(
    private val repository: FeedRepository,
    @IoDispatcher private val ioDispatcher: CoroutineDispatcher
) : ViewModel() {

    private val _state = MutableStateFlow(FeedState.Loading)
    val state: StateFlow<FeedState> = _state.asStateFlow()

    fun refresh() {
        viewModelScope.launch {
            _state.update { FeedState.Loading }
            val result = withContext(ioDispatcher) { repository.fetch() }
            _state.update {
                result.fold(
                    onSuccess = { FeedState.Loaded(it) },
                    onFailure = { FeedState.Error(it.message ?: "Unknown") }
                )
            }
        }
    }
}

// Composable — lifecycle-aware collection
@Composable
fun FeedScreen(viewModel: FeedViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    when (val s = state) {
        FeedState.Loading -> LoadingView()
        is FeedState.Loaded -> ItemList(s.items)
        is FeedState.Error -> ErrorView(s.message, onRetry = viewModel::refresh)
    }
}

// Repository — switch dispatcher inside the boundary, not at the top
class FeedRepository @Inject constructor(
    private val api: FeedApi,
    @IoDispatcher private val ioDispatcher: CoroutineDispatcher
) {
    suspend fun fetch(): Result<List<Item>> = runCatching {
        withContext(ioDispatcher) { api.getFeed() }
    }
}
```
