# Cancellation — cooperation and the exceptions that carry it

Cancellation in kotlinx.coroutines is a `CancellationException` thrown at suspension points. Two failure families: code that **swallows** the exception (the coroutine zombie-walks on), and code that **never reaches a suspension point** (the cancel never lands).

## The swallowing bugs — highest-priority findings

```kotlin
// 1. Broad catch around suspend code
try {
    repository.refresh()
} catch (e: Exception) {          // catches CancellationException too
    showError(e)                   // coroutine continues as if nothing happened
}

// Fix: rethrow cancellation first
try {
    repository.refresh()
} catch (e: CancellationException) {
    throw e
} catch (e: IOException) {
    showError(e)
}
```

```kotlin
// 2. runCatching around suspend code — same bug in nicer clothes
val r = runCatching { api.call() }   // captures CancellationException into Result.failure
```

`runCatching`/`Result.runCatching` wrapping suspension is acceptable only when the very next lines rethrow cancellation (`r.exceptionOrNull()?.let { if (it is CancellationException) throw it }`) — or when the project has a `runSuspendCatching` helper that does. Otherwise flag it.

Consequences of swallowing: `withTimeout` stops timing out, parent scopes wait forever on children that ignored the memo, "cancel and relaunch" patterns double-run.

## Cooperation checkpoints

Suspension points check for cancellation; straight-line CPU code does not:

```kotlin
// Uncancellable: tight loop, no suspension
items.forEach { heavyTransform(it) }

// Cooperative:
items.forEach {
    coroutineContext.ensureActive()   // or yield() to also give up the thread
    heavyTransform(it)
}
```

- Flag CPU-bound loops (parsing, image work, crypto) launched in cancellable contexts with no `ensureActive()`/`yield()`/`isActive` checks.
- Blocking I/O on `Dispatchers.IO` is *not* interrupted by cancellation — `runInterruptible { }` bridges cancellation to thread interruption for interruptible blocking calls (streams, JDBC).

## Cleanup paths

- `try/finally` runs on cancellation — correct place for releasing resources. But **suspending inside the `finally` of a cancelled coroutine throws immediately** unless wrapped:

  ```kotlin
  } finally {
      withContext(NonCancellable) {
          connection.closeGracefully()   // suspend cleanup that must complete
      }
  }
  ```

- `NonCancellable` outside that narrow cleanup idiom is a red flag — it detaches work from its parent's cancellation, the kotlin equivalent of `@unchecked`.
- `Flow`-side cleanup belongs in `onCompletion { }` (sees the cause) or `awaitClose { }` for `callbackFlow`.

## `withTimeout` edges

- `withTimeout` throws `TimeoutCancellationException` — **a subclass of `CancellationException`**. Code that rethrows all `CancellationException` will also rethrow timeouts; when a timeout is a *handled* outcome, prefer `withTimeoutOrNull` and branch on `null` rather than catch-and-classify.
- Catching `TimeoutCancellationException` *outside* the `withTimeout` block is too late — it has already cancelled the caller. Handle inside or use the `OrNull` variant.

## Review checklist

- Every `catch (e: Exception)` / `catch (e: Throwable)` / `runCatching` that can wrap a suspension → does cancellation escape?
- Long CPU loops → checkpoint present?
- `finally` blocks that suspend → `NonCancellable`-wrapped?
- Stop/cancel UX (a visible "stop generating" button, search-as-you-type) → does cancelling the `Job` actually halt the work it claims to?
