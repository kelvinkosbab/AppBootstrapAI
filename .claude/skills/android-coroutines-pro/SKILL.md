---
name: android-coroutines-pro
description: Deep-reviews Kotlin coroutines and Flow code for structured-concurrency correctness — scope and dispatcher discipline, cooperative cancellation, exception propagation, hot/cold flow patterns, and coroutine testing. Use when reading, writing, or reviewing concurrency-heavy Kotlin/Android code.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
  grounded_in: "kotlinx.coroutines docs, Android Developers coroutines/Flow guides, Android 'Now in Android' (https://github.com/android/nowinandroid)"
---

Review Kotlin coroutines and Flow code for correctness. This is the deep-review companion to the always-on `android-coroutines-best-practices.md` rule — the rule steers while writing; this skill audits what was written. The Android sibling of `swift-concurrency-pro`. Report only genuine problems; don't nitpick.

Review process:

1. Check scope and dispatcher discipline using `references/structured-concurrency.md` — every coroutine's lifetime tied to a real lifecycle, dispatchers injected.
2. Check cancellation cooperation using `references/cancellation.md` — `CancellationException` discipline, CPU-loop checkpoints, cleanup paths.
3. Check exception propagation using `references/exceptions.md` — `launch` vs `async` semantics, supervisor boundaries, handler placement.
4. Check Flow construction and exposure using `references/flows.md` — cold/hot boundaries, `stateIn`/`shareIn` configuration, operator semantics.
5. Check the tests using `references/testing.md` — virtual time, dispatcher substitution, Turbine discipline.

If doing a partial review, load only the relevant reference files.

## Core Instructions

- **Every coroutine needs an owner.** The first question for any `launch`/`async`: which scope, why that scope, and what cancels it. "Nothing cancels it" is a finding.
- **Cancellation is the invariant most code silently breaks.** Trace every broad `catch` and every `runCatching` around suspend code — swallowed `CancellationException` corrupts structured concurrency at a distance.
- **Distinguish bug classes from style.** A swallowed cancellation or a deferred `async` exception is correctness; a missing `flowOn` that happens to run on the right dispatcher anyway is a latent risk; name which is which.
- **Flow exposure is API design.** What a ViewModel/repository exposes (`StateFlow` vs `SharedFlow` vs cold `Flow`, replay, sharing policy) determines consumer behavior — review it like a public interface.
- **Suspend under a non-suspending lock is a deadlock pattern** (`synchronized`/`ReentrantLock` around suspension points) — always flag.
- Assume Kotlin 2.x, kotlinx.coroutines 1.8+, Hilt for injection. Dispatchers arrive via qualified injection (`@IoDispatcher`), never hardcoded at use sites.

## Output Format

Organize findings by file. For each issue: file/line, the violated principle, brief before/after. Skip clean files. End with a prioritized summary — correctness (cancellation/exceptions/leaks) first, then structure, then style.

Example finding:

### SyncRepository.kt

**Line 58: `runCatching` around suspend call swallows cancellation.**

```kotlin
// Before — cancellation is caught as failure; the coroutine keeps running "successfully"
val result = runCatching { api.sync() }

// After — rethrow cancellation; catch only what you can handle
val result = try {
    Result.success(api.sync())
} catch (e: CancellationException) {
    throw e
} catch (e: IOException) {
    Result.failure(e)
}
```

## References

- `references/structured-concurrency.md` — scope-to-lifecycle mapping, `repeatOnLifecycle`, dispatcher injection, `GlobalScope`/`runBlocking` bans, job hierarchy review.
- `references/cancellation.md` — cooperation checkpoints (`ensureActive`/`yield`), `CancellationException` discipline, `NonCancellable` cleanup, `withTimeout` edges.
- `references/exceptions.md` — `launch` vs `async` propagation, `coroutineScope` vs `supervisorScope`, `CoroutineExceptionHandler` placement, rethrow patterns.
- `references/flows.md` — cold vs hot, `stateIn`/`shareIn` + `WhileSubscribed(5_000)`, `flowOn` placement, `callbackFlow`/`awaitClose`, `collectLatest`/`flatMapLatest`/`conflate` semantics.
- `references/testing.md` — `runTest`, `StandardTestDispatcher` vs `UnconfinedTestDispatcher`, `MainDispatcherRule`, Turbine, `backgroundScope` for `stateIn`, virtual-time control.
