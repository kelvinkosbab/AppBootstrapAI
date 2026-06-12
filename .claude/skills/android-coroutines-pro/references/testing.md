# Testing coroutines — virtual time, dispatcher substitution, flow assertions

Coroutine tests fail in two characteristic ways: flaky (real time/threads leaked into the test) or vacuously green (assertions ran before the coroutine did). Both trace to the same root — work scheduled somewhere the test scheduler doesn't control.

## `runTest` and the scheduler

- **`runTest { }`** is the entry point — virtual time, auto-advance, fails on leaked coroutines at the end. `runBlocking` in tests forfeits virtual time (a `delay(30_000)` really waits); flag it.
- A `delay`/timeout that only works because the test waits in real time (`Thread.sleep`, `runBlocking { delay() }`, `awaitility`) is the flake factory — replace with virtual-time control.

## Dispatcher substitution — the linchpin

Virtual time only governs coroutines running on the **test scheduler**. Any hardcoded `Dispatchers.IO`/`Default` in production code escapes it — the test races a real thread pool:

```kotlin
// Production code takes the dispatcher (see structured-concurrency.md)…
class Repo @Inject constructor(@IoDispatcher private val io: CoroutineDispatcher)

// …so the test hands in the test dispatcher:
val repo = Repo(io = StandardTestDispatcher(testScheduler))
```

- A test that needed `Thread.sleep`/`advanceUntilIdle` *and still flakes* almost always has an un-substituted dispatcher somewhere in the code under test — that's the finding, not the test.
- **`Dispatchers.Main` needs `Dispatchers.setMain(...)`** before anything touches `viewModelScope`, and `resetMain()` after. The project should have one `MainDispatcherRule` (JUnit4 `TestWatcher`) instead of per-class boilerplate; flag copy-pasted setMain blocks.

## `StandardTestDispatcher` vs `UnconfinedTestDispatcher`

- **Standard** (default): coroutines don't run until the scheduler is pumped — `advanceUntilIdle()`, `advanceTimeBy(ms)`, `runCurrent()`. Deterministic control; the right default. Assertions placed right after a `viewModel.refresh()` with no pump test the *pre*-state — a classic vacuous-green.
- **Unconfined**: eagerly enters coroutines until first suspension — convenient for simple "did the state end up right" tests, but it erases ordering and intermediate states. Flag it where the test claims to verify a Loading→Loaded sequence.

## Flow assertions — Turbine

```kotlin
viewModel.state.test {
    assertEquals(UiState.Loading, awaitItem())
    viewModel.refresh()
    assertEquals(UiState.Loaded(items), awaitItem())
    cancelAndIgnoreRemainingEvents()
}
```

- Every `test { }` block must end consumed: `awaitComplete()`, `cancelAndIgnoreRemainingEvents()`, or `expectNoEvents()` — unconsumed events fail, which is the point; don't "fix" it by ignoring eagerly at the top.
- `StateFlow` conflates: a fast Loading→Loaded transition may surface only Loaded. A test asserting every intermediate state of a conflated flow is asserting scheduler luck — either use `StandardTestDispatcher` and pump between steps, or assert the final state only. Flag fragile intermediate assertions.
- Hand-rolled `val results = mutableListOf<T>(); launch { flow.toList(results) }` collection is replaceable with Turbine in almost every case — and usually hides a missing-cancel leak.

## `stateIn` / hot flows in tests

- A `stateIn(viewModelScope, WhileSubscribed, ...)` pipeline does nothing until subscribed — tests must collect (Turbine `.test{}` does) before asserting non-initial values.
- For flows shared in the test body, collect in **`backgroundScope`** (cancelled automatically by `runTest`) — a plain `launch { flow.collect{} }` never completes and fails the test at teardown.

## What not to write

- Tests asserting *implementation* (which dispatcher ran, how many coroutines launched) instead of observable state/effects.
- `advanceUntilIdle()` sprinkled until green without understanding what's pending — each pump should correspond to a named expectation.
- Mocked suspend functions returning instantly that mask real concurrency (a `coEvery { } returns x` world where races can't exist) — fine for logic tests; insufficient as the *only* coverage for cancel/retry behavior. Use fakes with controllable `CompletableDeferred` gates for those.
