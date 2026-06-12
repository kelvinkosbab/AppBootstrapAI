# Flow — construction, sharing, and operator semantics

Flow findings split into three families: cold/hot confusion, sharing misconfiguration, and operators whose semantics the author didn't actually want.

## Cold vs hot — who pays per collector

- A **cold `Flow`** runs its producer **per collector**. A repository returning `flow { api.fetch() ... }` collected in three places = three network calls. When the data should be shared, share deliberately (`shareIn`/`stateIn`) — don't rely on "we only collect once."
- **`StateFlow`** = hot, conflated, always-has-value → *state*. **`SharedFlow`** = hot, configurable replay → *events*. UI state in a `SharedFlow(replay=1)` is a hand-rolled worse `StateFlow`; one-shot events in a `StateFlow` re-deliver on every new collector (the rotation-re-shows-snackbar bug).
- One-shot event delivery is inherently lossy with `SharedFlow(replay=0)` when no collector is attached (e.g., during config change). For must-deliver events prefer modeling them *as state* the UI consumes-and-clears, or a `Channel(BUFFERED).receiveAsFlow()` — and flag whichever choice the code made if it doesn't match the delivery guarantee it needs.

## `stateIn` / `shareIn` configuration

```kotlin
val state: StateFlow<UiState> = combine(repo.user, repo.feed, ::buildState)
    .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), UiState.Loading)
```

- **`WhileSubscribed(5_000)`** is the Android default of choice: upstream stops when the UI is gone (no background burn), the 5s grace survives rotation without restarting the pipeline. `Eagerly`/`Lazily` keep the upstream alive for the scope's whole life — fine for app-scoped caches, wasteful in a ViewModel; flag mismatches.
- `stateIn` needs an `initialValue` that's honest — an empty-list initial that's indistinguishable from "loaded empty" pushes a `Loading` phase out of the model.
- Per-call sharing (`fun observe() = upstream.shareIn(scope, ...)`) creates a *new* share per invocation — share once in a property.
- Flag `MutableStateFlow`/`MutableSharedFlow` exposed publicly — expose `asStateFlow()`/`asSharedFlow()`.

## `flowOn` and context

- `flowOn` affects **upstream only**. `flow.flowOn(io).map { heavy() }` runs `heavy()` in the collector's context — the operator chain order is the finding.
- A flow builder doing blocking work with no `flowOn` inherits the collector's dispatcher (often Main). The producer owns its context, same main-safety convention as suspend functions.
- `withContext` *inside* a `flow { }` builder violates context preservation and throws — that's what `flowOn` is for.

## `callbackFlow` — the bridge with teardown

```kotlin
fun locations(): Flow<Location> = callbackFlow {
    val cb = object : LocationCallback() {
        override fun onLocationResult(r: LocationResult) { trySend(r.lastLocation) }
    }
    client.requestLocationUpdates(request, cb, looper)
    awaitClose { client.removeLocationUpdates(cb) }   // mandatory
}
```

- Missing `awaitClose` is both a leak *and* a runtime error path (the channel closes while the callback keeps firing). Always check it un-registers the exact registration.
- `trySend` (not `send`) inside non-suspending callbacks; if drops matter, check the buffer strategy (`.buffer(...)`).

## Operator semantics — latest vs every

| Intent | Operator | Trap when misused |
|---|---|---|
| Only newest matters; cancel in-flight work | `collectLatest` / `mapLatest` / `flatMapLatest` | body must be cancellation-safe (it *will* be cancelled mid-flight) |
| Every value matters | `collect` / `map` / `flatMapConcat` | slow consumer backpressures the producer |
| Skip intermediate values, keep latest | `conflate` | dropped values are invisible — wrong for events |
| Rate-limit user input | `debounce` | applied to *state* updates it just adds latency |

The classic pairing: search-as-you-type = `debounce(300)` + `distinctUntilChanged()` + `flatMapLatest { query -> repo.search(query) }` — each piece has a job; review deviations against intent.

- `catch { }` only sees **upstream** exceptions — placed before the `map` that throws, it misses it. `onCompletion` for cleanup, `retryWhen` for typed, backoff retry (never retry unconditionally).
- `.catch { emit(Fallback) }` that hides upstream *cancellation*: `catch` correctly ignores cancellation, but a manual `try/catch` inside `flow { }` doesn't — same rethrow discipline as everywhere.
