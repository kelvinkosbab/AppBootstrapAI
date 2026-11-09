---
name: android-memory-storage-pro
description: Audits Android apps for memory and on-device storage problems — Context, View, listener, and Fragment-binding leaks; bitmap decode size; unbounded caches; onTrimMemory handling; largeHeap; low-memory kills and process death; app-specific vs shared storage, broad storage permissions, SharedPreferences on the main thread, deprecated security-crypto, Auto Backup rules, unbounded disk caches, free-space handling, StrictMode, and app size. Use when investigating OOMs, leaks, LMK kills, storage complaints, Play storage-permission rejections, restore crashes, or when reviewing code that caches, decodes images, or writes files.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
  grounded_in: "Android Developers guides on managing app memory, ComponentCallbacks2.onTrimMemory (Android 14 level changes), bitmap loading, LeakCanary 2.x, Memory Profiler and dumpsys meminfo, ApplicationExitInfo, data and file storage overview, scoped storage, MediaStore, Photo Picker, Storage Access Framework, Play's photo and video permissions and All files access policies, Jetpack DataStore, Room, Android Keystore, Auto Backup and data extraction rules, StorageManager, StrictMode, Play Asset Delivery"
---

Audit Android code for memory and storage problems. This is the deep-review companion to the always-on `android-memory-management.md` and `android-storage-management.md` rules: the rules steer while writing; this skill traces ownership, footprint, and file placement across whole features and the manifest. Report only genuine problems.

Applies to Compose and View-based apps. If asked to **fix** rather than review, make the changes directly and summarize them in the same file-by-file format.

Review process:

1. **Leaks.** For every long-lived object (singletons, `object`s, companion objects, ViewModels, Hilt `@Singleton`s, services), check what it holds and what it registers, using `references/leaks.md`. Confirm the reference chain from a GC root before reporting.
2. **Footprint.** Check image loading, in-memory caches, list loading, trim-memory handling, and manifest heap flags using `references/memory-footprint.md`.
3. **Storage.** For every file write, preference, database, permission, and backup rule, check location, API, threading, size caps, and backup behavior using `references/storage-layout.md`.
4. **Evidence.** When the user reports a symptom (OOM, LMK kills, ANRs on disk, storage growth), or before you claim a fix worked, use `references/measuring.md` to reproduce and confirm it with LeakCanary, the Memory Profiler, `dumpsys`, StrictMode, or `ApplicationExitInfo`.

For a partial review (only leaks, only storage), load only the matching reference.

**Official companion:** when Google's Android skills ([android/skills](https://github.com/android/skills), Apache-2.0) are installed, see `android-profiler` (Android Studio profilers and PerfettoSQL). Use it to gather evidence in step 4; this skill decides what the evidence means and what to fix.

## Core Instructions

- **A leak finding names the chain**: `AnalyticsTracker` (singleton) → `listener` → `ProfileFragment` → its view tree. "Might leak" without a chain isn't a finding.
- **Size findings in bytes**: "decodes a 4000×3000 photo as ARGB_8888 for a 64dp avatar: ~48 MB" is actionable.
- **Storage findings name the consequence**: Play rejection (broad storage or media permissions), restore crash (Keystore-encrypted file in backup), data loss (needed files in `cacheDir`), ANR (`commit()` on the main thread), or growth without bound.
- **Severity by user impact**: crash or data loss (OOM on a common flow, restore crash, Play policy violation, secrets in plain files) > degraded (leaked screens, unbounded caches, main-thread I/O, backup bloat) > hygiene (no StrictMode in debug, missing cache cap on a small cache).
- Cross-reference, don't duplicate: coroutine scope lifetime belongs to `android-coroutines-pro`; recomposition cost to `android-compose-pro`; R8 and resource shrinking to `r8-shrink-pro`; module placement of data sources to `android-modularization-pro`.

## Output Format

Organize findings by file. For each issue: file/line, the problem, the measured or estimated cost (bytes, objects, or files), and a brief before/after. Skip clean files. End with a prioritized summary.

Example finding:

### LocationTracker.kt

**Line 14: a singleton holds the Activity it was first called from, leaking that screen for the life of the process.**

```kotlin
// Before
object LocationTracker {
    private lateinit var context: Context
    fun start(context: Context) { this.context = context; /* ... */ }
}

// After: inject the application context; nothing screen-scoped is stored
@Singleton
class LocationTracker @Inject constructor(
    @ApplicationContext private val context: Context,
)
```

### Summary

1. **Crash risk:** `AvatarView` decodes full-size photos (~48 MB each) with `BitmapFactory.decodeFile`; OOM on low-RAM devices.
2. **Play policy:** `READ_MEDIA_IMAGES` requested to pick one profile photo; use the Photo Picker.
3. **Degraded:** `LocationTracker` leaks the first Activity; SharedPreferences `commit()` on the main thread in `SettingsViewModel`.

End of example.

## References

- `references/leaks.md` — Context and View references in long-lived objects, listeners and callbacks, Compose `DisposableEffect`, Fragment view binding, handlers and inner classes, services, WebView.
- `references/memory-footprint.md` — bitmap sizing with Coil and ImageDecoder, LruCache sizing, onTrimMemory levels on Android 14+, Paging, hot-path allocation, largeHeap, low-RAM devices, process death.
- `references/storage-layout.md` — the location decision table, scoped storage, MediaStore, Photo Picker, SAF, Play permission policies, DataStore and Room, Keystore encryption, Auto Backup rules, AtomicFile, free space and cache quotas, app size.
- `references/measuring.md` — LeakCanary (debug and instrumentation), Memory Profiler heap dumps, `dumpsys meminfo`, `ApplicationExitInfo`, Macrobenchmark, Perfetto, StrictMode, inspecting app storage with `adb`.
