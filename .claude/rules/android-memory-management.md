---
description: Memory on Android — Context, View, and listener leaks; LeakCanary; bitmap sizing with Coil and ImageDecoder; LruCache and onTrimMemory; Paging for large lists; largeHeap; low-memory kills and process death; measuring with the Memory Profiler, dumpsys meminfo, and ApplicationExitInfo
globs: "**/*.{kt,kts,xml}"
paths:
  - "**/*.{kt,kts,xml}"
must:
  - "Never hold an Activity, Fragment, View, or Activity Context in a singleton, object, companion object, or ViewModel."
  - "Unregister every listener, receiver, and callback in the lifecycle callback that matches its registration."
  - "Decode bitmaps at display size (Coil, `ImageDecoder.setTargetSize`, `inSampleSize`), never at full resolution."
  - "Never set `android:largeHeap` to hide memory problems; bound caches and fix leaks instead."
---

# Android Memory Management

Every app runs with a per-process heap limit, and the low-memory killer ends background processes first. A leaked `Activity` keeps its whole view tree and bitmaps alive; enough of them and the app dies with an `OutOfMemoryError` or gets killed as soon as the user switches away. These are the must-follow rules. Examples and the audit workflow live in the **`android-memory-storage-pro`** skill (`references/leaks.md`, `references/memory-footprint.md`, `references/measuring.md`).

## Leaks

- **Never keep an `Activity`, `Fragment`, `View`, or Activity `Context` in a singleton, `object`, companion object, or ViewModel.** Use `applicationContext` (Hilt: `@ApplicationContext`) for long-lived work. `@SuppressLint("StaticFieldLeak")` is a leak, not a fix.
- **Unregister everything you register, in the matching lifecycle callback**: listeners, `BroadcastReceiver`s, sensor and location callbacks, `OnBackPressedCallback`s added without a lifecycle owner. In Compose, register in `DisposableEffect` and unregister in `onDispose`.
- **Fragments with view binding null the binding in `onDestroyView()`**; the fragment outlives its view on the back stack.
- **No anonymous `Handler`, `Runnable`, or inner class that outlives the screen** while holding the Activity. Use coroutines in `lifecycleScope` / `viewModelScope` (`android-coroutines-best-practices.md`).
- **LeakCanary in every debug build** (`debugImplementation`), and leaks it reports are bugs to fix before release.

## Footprint

- **Decode bitmaps at display size.** Load images through Coil (or Glide), which sizes to the target; in Compose `AsyncImage` sizes to its constraints. Manual decoding uses `ImageDecoder.setTargetSize` or `BitmapFactory.Options.inSampleSize` after an `inJustDecodeBounds` pass; never decode a camera photo at full resolution for a thumbnail.
- **In-memory caches are bounded**: `LruCache` sized from `ActivityManager.memoryClass` (for example one eighth), never an unbounded `HashMap` in a singleton.
- **Release caches in `onTrimMemory`** (`ComponentCallbacks2`). From Android 14 only `TRIM_MEMORY_UI_HIDDEN` and `TRIM_MEMORY_BACKGROUND` are delivered; release UI-only memory at the first and caches at `level >= TRIM_MEMORY_BACKGROUND`.
- **Page large datasets** with Paging 3 instead of holding a whole table in a `StateFlow<List<…>>`; lazy lists with stable `key`s.
- **No allocation in hot paths**: `onDraw`, Compose `drawBehind` / `Canvas` lambdas, per-frame animation callbacks, and tight loops.
- **`android:largeHeap="true"` is not a fix.** It hides leaks, isn't honored on every device, and makes GC pauses longer. Fix the footprint.
- **Check `ActivityManager.isLowRamDevice()`** and scale caches, prefetching, and image quality down on low-RAM devices (Android Go).
- **Stop services when the work ends**; prefer WorkManager to a long-running background service.

## Process death

- **Assume the process is killed in the background.** UI state that matters survives via `SavedStateHandle` / `rememberSaveable`; persistent state lives in Room or DataStore.
- **Read field data**: `ActivityManager.getHistoricalProcessExitReasons()` reports `REASON_LOW_MEMORY` kills; track them alongside OOM crashes in your crash reporter.

## Measure

- **Android Studio Memory Profiler**: heap dump after leaving a screen (activities and fragments still present are leaks); record Java/Kotlin allocations for churn.
- **`adb shell dumpsys meminfo <package>`** for the PSS breakdown (Java heap, native, graphics); compare before and after a flow.
- **Instrumented leak checks**: `leakcanary-android-instrumentation`'s `DetectLeaksAfterTestSuccess` rule in UI tests.
- Macrobenchmark `MemoryUsageMetric` (experimental) for memory-heavy journeys; Perfetto heap profiles for native memory.
