# Exception propagation — builders, supervisors, handlers

Coroutine exceptions don't behave like function exceptions: *where* a failure surfaces depends on the builder, the job hierarchy, and supervisor boundaries. Most "random crash from a coroutine" reports are a mismatch between where the author put the `try` and where the exception actually travels.

## `launch` vs `async` — two delivery mechanisms

- **`launch`**: exceptions propagate **up the job tree immediately** — they cancel the parent (unless a supervisor intervenes) and reach the scope's `CoroutineExceptionHandler` (or crash). A `try` *around the `launch` call* catches nothing:

  ```kotlin
  // WRONG: launch returns instantly; the failure happens later, elsewhere
  try { scope.launch { risky() } } catch (e: IOException) { ... }

  // RIGHT: catch inside the coroutine
  scope.launch {
      try { risky() } catch (e: IOException) { handle(e) }
  }
  ```

- **`async`**: exceptions are **deferred until `await()`** — but *also* still cancel the parent job at throw time unless the parent is a supervisor. The notorious composite: `scope.async { }` whose `Deferred` is never awaited → silently dropped failure (under a supervisor) or a delayed scope-cancel surprise (without). Every `async` needs a visible `await` path; `async { }` used as fire-and-forget is a finding — that's `launch`.

## `coroutineScope` vs `supervisorScope`

- **`coroutineScope { }`**: one child fails → siblings cancelled → the exception rethrows at the call site. The right default — failures are caught with ordinary `try` around the `coroutineScope` call. All-or-nothing parallel decomposition:

  ```kotlin
  suspend fun loadDashboard(): Dashboard = coroutineScope {
      val user = async { api.user() }
      val feed = async { api.feed() }
      Dashboard(user.await(), feed.await())   // either failure cancels the other fetch
  }
  ```

- **`supervisorScope { }`**: children fail independently — but each child's failure must then be handled *at that child* (`try` inside it, or a per-child `await`); an unhandled `launch` failure inside a supervisor goes to the `CoroutineExceptionHandler`/crash. A `supervisorScope` whose children have no per-child handling hasn't isolated anything — it's only relocated the crash. Flag supervisors used as a reflex.
- `viewModelScope` is supervisor-based: one crashed `launch` doesn't kill the scope — but it *does* reach the default handler and crash the app if uncaught. "It's viewModelScope so exceptions are fine" is a misconception worth correcting in review.

## `CoroutineExceptionHandler` placement

- A `CoroutineExceptionHandler` works only installed at the **root** — the scope's context or a top-level `launch`. On a child `launch`/`async`/`withContext` it is silently ignored. Misplaced handlers are a common find.
- Its job is *last-resort reporting* (crash analytics, "something went wrong" surface) — not control flow. Business recovery (retry, error states) belongs in `try` at the suspend call.

## Patterns to flag

- **`catch (e: Throwable)`** — also swallows `Error`s and cancellation; almost never right.
- **Catch-log-continue** in repositories that makes callers see success-shaped `null`/empty values — push a typed failure (`Result`, sealed outcome) instead so the UI can distinguish.
- **Result-type boundaries**: `runCatching` at the repository boundary is acceptable *with* the cancellation-rethrow discipline (see `references/cancellation.md`); inside business logic it hides control flow.
- **Retry loops around suspend calls** that don't distinguish failure types — retrying a 401 or a `CancellationException` is a bug; retry IO-shaped failures with backoff (`retryWhen` on flows).
- `withContext` failures propagate like plain function calls (no deferral) — flag redundant machinery around it.
