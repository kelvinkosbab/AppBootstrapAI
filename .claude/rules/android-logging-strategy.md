---
description: Logging strategy for Android — Timber over android.util.Log, tag conventions, level discipline, stripping debug logs from release, no PII/secrets, crash-reporter integration, Logcat hygiene
globs: "**/*.{kt,kts}"
---

# Android Logging Strategy

Two problems with naive Android logging: raw `android.util.Log` calls ship to production (leaking data, costing cycles, cluttering users' Logcat), and there's no central place to route logs to a crash reporter. **Timber** solves both — a thin façade over `Log` that you plant once and control globally. This rule pins the conventions; for the R8 keep/strip rules that remove debug logs from release, see [`r8-shrink-pro`](../skills/r8-shrink-pro/SKILL.md) and the gradle-conventions rule.

## Use Timber, Not `android.util.Log`

- **[Timber](https://github.com/JakeWharton/timber)** is the de-facto standard. `Timber.d("…")`, `Timber.e(throwable, "…")`. Plant a tree in `Application.onCreate()`:

  ```kotlin
  class MyApp : Application() {
      override fun onCreate() {
          super.onCreate()
          if (BuildConfig.DEBUG) {
              Timber.plant(Timber.DebugTree())          // verbose logs in debug only
          } else {
              Timber.plant(CrashReportingTree())        // route to Crashlytics/Sentry in release
          }
      }
  }
  ```

- **Never call `android.util.Log` directly in app code** — it can't be globally redirected, stripped, or routed to a crash reporter. Timber wraps it; use the wrapper.
- **Timber auto-tags** with the calling class name — don't pass a manual tag unless you need a specific one (`Timber.tag("Sync").d(...)`).

## Log Levels — When Each

| Level | Method | Use for |
|-------|--------|---------|
| VERBOSE | `Timber.v` | Fine-grained tracing; rarely needed. |
| DEBUG | `Timber.d` | Developer diagnostics — gone in release (see stripping). |
| INFO | `Timber.i` | Notable lifecycle/state events worth keeping. |
| WARN | `Timber.w` | Recoverable oddities — degraded but working. |
| ERROR | `Timber.e` | Errors — something failed; pass the `Throwable`. |
| ASSERT | `Timber.wtf` | "Should never happen" — programmer error. |

- **Pass the `Throwable` as the first arg**, don't string-concatenate it: `Timber.e(exception, "Upload failed for %s", id)` — the tree gets the real stack trace, and crash reporters log it as a non-fatal.
- **Use Timber's format args** (`"%s"`, `"%d"`) rather than Kotlin string templates for the message — the args are only formatted if the log is actually emitted (lazy), and the crash reporter can group by the format string.
- **Match level to severity** — a `Timber.e` that fires routinely desensitizes everyone to real errors.

## Stripping Debug Logs From Release

Debug logs must not ship — they cost cycles, clutter users' Logcat, and can leak data. Two layers:

1. **DebugTree only in debug** (above) — in release you plant a tree that drops `VERBOSE`/`DEBUG` and forwards `INFO`+ to the crash reporter. This is the primary control.
2. **R8 `assumenosideeffects`** to physically remove `Log.*` calls (and optionally Timber's verbose/debug) from the release bytecode:

   ```proguard
   # proguard-rules.pro — strip android.util.Log.v/d at the bytecode level
   -assumenosideeffects class android.util.Log {
       public static int v(...);
       public static int d(...);
   }
   ```

   - This eliminates even the argument-evaluation cost. Use it for any stray direct `Log` calls.
   - **Don't `assumenosideeffects` on `Log.e`/`Log.w`** — you want errors/warnings in release.
   - See `r8-shrink-pro` for the keep-rule discipline around this.

## No PII / Secrets

- **Never log** auth tokens, API keys, passwords, full request/response bodies, or precise PII (email, full name, location, device IDs).
- **Log a correlation ID** (a hash or a request UUID) instead of the sensitive value — enough to match occurrences, not to expose data.
- **A release tree is a second line of defense** — strip or redact known-sensitive fields in `CrashReportingTree.log()` before forwarding, so a stray sensitive log doesn't reach a third-party crash service.
- **Remember Logcat is world-readable to other apps on rooted/dev devices** and shows up in bug reports — treat it as semi-public.

## Crash-Reporter Integration

The release tree is where logging meets crash reporting:

```kotlin
private class CrashReportingTree : Timber.Tree() {
    override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
        if (priority == Log.VERBOSE || priority == Log.DEBUG) return   // drop noise

        // Breadcrumbs: recent logs attached to the next crash.
        Firebase.crashlytics.log(message)
        if (t != null && priority >= Log.WARN) {
            Firebase.crashlytics.recordException(t)                     // non-fatal report
        }
    }
}
```

- **Breadcrumbs** — forward `INFO`+ messages so a crash report carries the log trail that led to it.
- **Non-fatals** — `recordException` for caught `Throwable`s at `WARN`/`ERROR` you want to track without crashing. (Sentry: `Sentry.captureException` / `addBreadcrumb`.)
- **Don't double-report** — if you both `Timber.e(t, …)` and manually `recordException(t)` at the call site, you get two reports. Let the tree own forwarding.

## Threading / Coroutines Context

- **Include enough context to correlate** across threads — a request ID or screen name in the message, since async logs interleave in Logcat.
- **Don't log inside tight loops or hot Compose recomposition** at `DEBUG`+ — it floods Logcat and can affect frame timing. Gate per-frame detail behind VERBOSE.

## Common Pitfalls

- **Direct `android.util.Log` in app code** — can't be stripped, redirected, or routed to crash reporting. Use Timber.
- **Debug logs shipping in release** — no release-specific tree and no R8 stripping. Both layers matter.
- **String-concatenating the exception** (`Timber.e("failed: $e")`) — loses the stack trace and the crash reporter's grouping. Pass the `Throwable`.
- **Logging tokens/PII/bodies** — leaks to Logcat and (via breadcrumbs) to a third-party crash service.
- **Manual tags everywhere** — Timber auto-tags with the class; manual tags drift and duplicate.
- **`assumenosideeffects` on `Log.e`** — you just deleted your release error logs.
- **Double-reporting non-fatals** — both call-site `recordException` and a forwarding tree.
- **Kotlin string templates instead of Timber format args** — eager formatting even when the log is dropped.

## Patterns to Follow

```kotlin
// Application.onCreate — plant once, branch on build type.
if (BuildConfig.DEBUG) {
    Timber.plant(Timber.DebugTree())
} else {
    Timber.plant(CrashReportingTree())
}

// Usage — auto-tagged, lazy args, Throwable passed through.
Timber.d("Loading feed for %s", userId.hashCode())             // stripped in release
try {
    repository.refresh()
    Timber.i("Feed refreshed: %d items", items.size)
} catch (e: IOException) {
    Timber.e(e, "Feed refresh failed for %s", userId.hashCode())  // → non-fatal in release
}
```

```proguard
# Release: strip verbose/debug Log calls entirely.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
}
```
