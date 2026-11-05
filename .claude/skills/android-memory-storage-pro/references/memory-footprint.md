# Memory footprint

Each app process has a Java/Kotlin heap limit (`ActivityManager.memoryClass`, in MB) far below the device's RAM, plus native and graphics memory that count toward the system's view of the process. Bitmaps are the usual way to blow through it.

## Bitmaps

Decoded size is `width × height × bytes per pixel`: 4 for `ARGB_8888`, 2 for `RGB_565`, 8 for `RGBA_F16`. A 4000 × 3000 photo is ~48 MB as ARGB_8888.

**Use an image library.** Coil (Compose-first) and Glide decode at the target size, pool and cache bitmaps, and cancel work when the view goes away.

```kotlin
// Compose: Coil sizes the request from the composable's constraints
AsyncImage(
    model = ImageRequest.Builder(LocalContext.current)
        .data(photo.url)
        .crossfade(true)
        .build(),
    contentDescription = null,
    modifier = Modifier.size(64.dp),
)
```

- With `Modifier.wrapContentSize()` or unconstrained sizes, Coil can't infer a target size and may load the original. Constrain the composable or set `.size(...)` on the request.
- Coil uses hardware bitmaps on API 26+ by default (pixels in graphics memory, not the Java heap). Disable them only where you read pixels in software.

**Manual decoding** (non-UI work, exports):

```kotlin
// API 28+: decode straight to the target size
val bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
    val scale = maxOf(info.size.width / targetPx, info.size.height / targetPx, 1)
    decoder.setTargetSize(info.size.width / scale, info.size.height / scale)
}

// Older APIs: read bounds first, then sample
val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
BitmapFactory.decodeFile(path, bounds)
val options = BitmapFactory.Options().apply {
    inSampleSize = calculateInSampleSize(bounds.outWidth, bounds.outHeight, targetPx)
}
val sampled = BitmapFactory.decodeFile(path, options)
```

- `inSampleSize` works in powers of two; follow it with a scale if you need an exact size.
- Don't call `Bitmap.recycle()` in new code; drop references and let the library's pool or GC reclaim them.

## In-memory caches

```kotlin
val memoryClassMb = context.getSystemService<ActivityManager>()!!.memoryClass
val cache = object : LruCache<String, Bitmap>(memoryClassMb * 1024 * 1024 / 8) {
    override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
}
```

- Size in bytes with `sizeOf`, not entry count, when entries vary in size.
- A `HashMap` or `mutableMapOf` in a singleton keyed by IDs or URLs never shrinks. Flag it when values are large or keys are unbounded.
- Don't build a second bitmap cache next to Coil's; configure Coil's `memoryCache { maxSizePercent(context, 0.25) }` instead.

## onTrimMemory

Implement `ComponentCallbacks2` (on `Application`, or register with `registerComponentCallbacks`).

```kotlin
override fun onTrimMemory(level: Int) {
    if (level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND) {
        imageLoader.memoryCache?.clear()
        thumbnailCache.evictAll()
    } else if (level >= ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN) {
        releaseUiOnlyResources()
    }
}
```

- From Android 14 (API 34), only `TRIM_MEMORY_UI_HIDDEN` and `TRIM_MEMORY_BACKGROUND` are delivered; the `RUNNING_*`, `MODERATE`, and `COMPLETE` levels are deprecated. Compare with `>=`, never `==`, so code written for the old levels still frees memory.
- A smaller process in the background is less likely to be killed, so freeing caches here directly improves warm-start rates.

## Lists and data

- Paging 3 (`Pager` + `PagingSource`, `collectAsLazyPagingItems()`) for anything that grows: feeds, message history, search results. Room can emit a `PagingSource` directly.
- A `StateFlow<List<T>>` holding a whole table re-emits and diffs the whole list on every change.
- `LazyColumn` / `RecyclerView` with stable keys; never a `Column` with `forEach` over hundreds of rows.
- Load full-size details on the detail screen, not in list items.

## Hot paths

- No object allocation in `onDraw`, `View.onMeasure`/`onLayout`, Compose `Canvas` / `drawBehind` / `drawWithContent` lambdas, or per-frame animation callbacks. Hoist `Paint`, `Path`, and `Rect` objects; in Compose, `remember` them or use `drawWithCache`.
- Boxing in tight loops: `List<Int>` boxes; `IntArray` doesn't. Matters only in measured hot paths.
- Chained collection operators on large lists allocate an intermediate list per step; `asSequence()` avoids that for long chains.

## largeHeap

`android:largeHeap="true"` asks for a bigger heap. It isn't guaranteed (the device decides), it makes every GC pass slower, and it makes the process a bigger target for the low-memory killer. It's justified only for apps whose core feature genuinely needs it (photo editors on large canvases) after the footprint is already tight. As a response to OOMs, it's a finding.

## Low-RAM devices

- `ActivityManager.isLowRamDevice()` is true on Android Go and other low-memory devices. Scale caches, prefetch depth, image quality, and animation down.
- The heap limit on these devices can be a fraction of a flagship's; test on one (or an emulator with 1–2 GB RAM).

## Process death

- The system kills cached background processes to reclaim memory; this is normal, not a crash. The app must restore the screen the user left.
- Save UI state with `SavedStateHandle` (ViewModel) and `rememberSaveable` (Compose). Keep it small; the saved state bundle is limited (around 1 MB per transaction) and large bundles crash with `TransactionTooLargeException`.
- Test it: Developer options → "Don't keep activities", or `adb shell am kill <package>` while the app is in the background, then return to it.
