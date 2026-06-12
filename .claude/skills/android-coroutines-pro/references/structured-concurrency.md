# Structured concurrency — scopes, lifecycles, dispatchers

Every coroutine must die with something. The review starts by mapping each `launch`/`async` to its owner and asking whether that owner's lifetime matches the work's.

## Scope-to-lifetime mapping

| Work lifetime | Owner |
|---|---|
| Tied to a ViewModel | `viewModelScope` |
| Tied to a visible UI / lifecycle state | `lifecycleScope` + `repeatOnLifecycle(STARTED)` |
| Tied to a composition | `LaunchedEffect` / `rememberCoroutineScope` |
| Must survive the screen but not process death | application-scoped `CoroutineScope` injected as a dependency (`@Singleton`, `SupervisorJob() + Dispatchers.Default`) |
| Must survive process death | `WorkManager` — not a coroutine scope at all |

Findings to raise:

- **`GlobalScope`** — unowned work; leaks past every lifecycle; invisible to tests. Replace per the table. No app-code exceptions.
- **`CoroutineScope(Dispatchers.IO)` created ad-hoc** at a call site — an unsupervised, never-cancelled scope; same disease as `GlobalScope` with extra steps. If a long-lived scope is genuinely needed, it's *injected*, named, and cancelled by an owner.
- **`runBlocking` in app code** — blocks the calling thread, inverts structured concurrency, ANRs on main. Tests and `main()` only.
- **Screen-lifetime work in `viewModelScope` that must complete** (e.g., "save on exit") — it dies with the ViewModel; route through the injected app scope or WorkManager, deliberately.

## UI collection — `repeatOnLifecycle`

```kotlin
// View-world collection done right:
viewLifecycleOwner.lifecycleScope.launch {
    viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
        viewModel.state.collect { render(it) }
    }
}
```

- `launchWhenStarted`/`launchWhenResumed` are deprecated — they *suspend* the producer but keep the upstream flow active; `repeatOnLifecycle` cancels and restarts collection. Flag the deprecated forms.
- In Compose, `collectAsStateWithLifecycle()` already encodes this — hand-rolled `LaunchedEffect { viewModel.state.collect { ... } }` loses the lifecycle pause; flag it.

## Dispatcher discipline

- **Inject dispatchers** via qualifiers; never `Dispatchers.IO` at a use site:

  ```kotlin
  class FeedRepository @Inject constructor(
      private val api: FeedApi,
      @IoDispatcher private val io: CoroutineDispatcher,
  ) {
      suspend fun fetch(): Feed = withContext(io) { api.fetch() }
  }
  ```

  Hardcoded dispatchers make virtual-time testing impossible (see `references/testing.md`).
- **Switch at the boundary, not the call site**: the suspending function that *does* blocking work owns its `withContext` — callers shouldn't need to know ("main-safety" convention). A ViewModel wrapping every repository call in `withContext(io)` means the repository broke the contract.
- **`Dispatchers.Main.immediate` vs `Main`** — only relevant when re-dispatch ordering is observable; treat unexplained `.immediate` as a question, not a finding.
- **Room/Retrofit suspend functions are already main-safe** — wrapping them in `withContext(IO)` is harmless noise; flag only as style.

## Job hierarchy review

- A stored `private var job: Job?` + manual `cancel()` is sometimes right (restartable search, one-at-a-time generation) — check the pair: every assignment cancels the predecessor, and nothing leaks on owner teardown.
- `job.cancelChildren()` vs `job.cancel()` confusion: cancelling a scope's job kills the scope permanently — later `launch`es silently no-op. A scope that "stops working" after one error/cancel usually hit this.
- Passing a `Job()` into `withContext`/`async` context breaks parent-child linkage (exceptions and cancellation no longer propagate) — almost always a bug.
