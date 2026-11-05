# Measuring memory and storage

Confirm a suspected problem before reporting it as certain, and confirm a fix before calling it done.

## LeakCanary

```kotlin
// app/build.gradle.kts (version from the catalog)
dependencies {
    debugImplementation(libs.leakcanary.android)
}
```

- No code needed; it watches destroyed Activities, Fragments, Fragment views, ViewModels, and services, dumps the heap when one is retained, and shows the reference chain.
- Read the chain from the GC root down. The first reference marked as suspect (underlined) is usually the one to cut.
- Watch your own objects: `AppWatcher.objectWatcher.expectWeaklyReachable(obj, "reason")` when something should be gone.
- **In instrumented tests**, fail on leaks:

```kotlin
@get:Rule
val rules: RuleChain = RuleChain.outerRule(DetectLeaksAfterTestSuccess())
    .around(createAndroidComposeRule<MainActivity>())
```

(`androidTestImplementation(libs.leakcanary.android.instrumentation)`.)

## Android Studio Memory Profiler

- **Heap dump**: open a screen, leave it, force GC, capture a heap dump. Filter by your package; Activities or Fragments still listed (with "Show activity/fragment leaks") are leaks. Sort by retained size to find what's large.
- **Record Java/Kotlin allocations** during a flow (scrolling a feed) to find churn: thousands of short-lived allocations per frame cause GC jank.
- **Native allocations** (API 29+) for native libraries and bitmaps on older APIs.
- Profile a release-like build (`profileable` or a non-debuggable benchmark variant) for realistic numbers; debug builds allocate more.

## dumpsys meminfo

```bash
adb shell dumpsys meminfo com.example.app
```

- **Total PSS** / **Total RSS** is what the system weighs when choosing whom to kill.
- Breakdown: **Java Heap**, **Native Heap**, **Graphics** (hardware bitmaps, textures), **Code**, **Stack**. A large Graphics number with a grid of images means oversized decodes.
- **Objects** section counts Activities and Views: an Activity count that grows with each visit to a screen is a leak.
- Compare before and after a flow, after forcing background (`adb shell input keyevent KEYCODE_HOME`).

## Simulating memory pressure

```bash
adb shell am send-trim-memory com.example.app BACKGROUND
adb shell am kill com.example.app      # while backgrounded: simulates a low-memory kill
```

Then return to the app: the screen and its state should be restored. Developer options → "Don't keep activities" exercises the same path continuously.

## Field data

- `ActivityManager.getHistoricalProcessExitReasons(packageName, 0, 20)` (API 30+) lists recent exits with `reason` (`REASON_LOW_MEMORY`, `REASON_CRASH`, `REASON_ANR`, …) and `pss` / `rss` at exit. Report low-memory kills and their PSS to analytics on next launch.
- Crash reporters group `OutOfMemoryError`s; the stack shows the last allocation, not the cause, so pair them with heap evidence.
- Android vitals in Play Console for ANRs (disk I/O on the main thread shows up here) and crash rates by device RAM.

## Macrobenchmark and Perfetto

- Macrobenchmark `MemoryUsageMetric` (experimental) records memory during a benchmarked journey; use it to guard memory-heavy flows against regressions.
- Perfetto with `heapprofd` for native heap profiles, and Java heap dumps from the command line, on release-like builds.

## StrictMode

```kotlin
if (BuildConfig.DEBUG) {
    StrictMode.setThreadPolicy(
        StrictMode.ThreadPolicy.Builder()
            .detectDiskReads()
            .detectDiskWrites()
            .penaltyLog()
            .build()
    )
    StrictMode.setVmPolicy(
        StrictMode.VmPolicy.Builder()
            .detectLeakedClosableObjects()
            .detectActivityLeaks()
            .detectLeakedRegistrationObjects()
            .penaltyLog()
            .build()
    )
}
```

Set it in `Application.onCreate()`. Some framework and library calls trip disk-read detection at startup; fix yours and note the rest.

## Storage inspection

```bash
adb shell run-as com.example.app du -h -d 2 .          # debuggable builds: the private data dir
adb shell dumpsys diskstats                            # per-app code, data, and cache sizes
adb shell bmgr backupnow com.example.app               # run a backup now; logcat shows what was included
```

- Android Studio's Device Explorer shows `/data/data/<package>` for debuggable builds.
- Settings → Apps → [app] → Storage shows App size, User data, and Cache. User data that only grows means no cleanup.
- Test a full disk: fill the emulator's data partition and run the app's download and save flows; expect a message, not a crash.
