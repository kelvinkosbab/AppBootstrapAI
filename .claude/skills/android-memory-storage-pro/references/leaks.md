# Leaks

A leak on Android is an object that should be garbage collected but is still reachable from a GC root (a static field, a running thread, a registered system callback). The costly ones are `Activity`, `Fragment` views, and `View`s, because each holds its whole view tree, its resources, and often bitmaps.

## Long-lived holders

These live as long as the process. Anything screen-scoped they reference leaks.

- Kotlin `object`s and companion objects.
- Hilt `@Singleton` and `@ActivityRetainedScoped` bindings.
- ViewModels (they outlive the Activity across configuration changes).
- `Application` subclasses.
- Static caches and registries.

```kotlin
// Leak: the ViewModel survives rotation; the Activity it holds doesn't
class ProfileViewModel(private val activity: Activity) : ViewModel()

// Fixed: pass what the work needs, or the application context
@HiltViewModel
class ProfileViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val repository: ProfileRepository,
) : ViewModel()
```

- A Context parameter isn't the problem; storing it is. A function that uses a Context and returns doesn't leak.
- `AndroidViewModel` gets the `Application`, which is safe, but ViewModels usually don't need a Context at all: move Context-dependent work into a repository or data source.
- `@SuppressLint("StaticFieldLeak")` silences the lint check for exactly this leak.
- Theme- or locale-dependent work (inflating views, resolving themed attributes, `getString` with per-Activity locale) needs the Activity context; do it in the screen, not in a singleton.

## Listeners and callbacks

Registering a callback hands the system (or a long-lived object) a reference to your code and everything it captures.

| Register | Unregister | Lifecycle pair |
|---|---|---|
| `registerReceiver` | `unregisterReceiver` | `onStart` / `onStop` |
| `SensorManager.registerListener` | `unregisterListener` | `onResume` / `onPause` |
| `LocationManager.requestLocationUpdates`, FusedLocation | `removeUpdates` | `onStart` / `onStop` |
| `ConnectivityManager.registerNetworkCallback` | `unregisterNetworkCallback` | match the owner |
| Your own `addListener` on a singleton | `removeListener` | match the owner |
| `ViewTreeObserver.addOnGlobalLayoutListener` | `removeOnGlobalLayoutListener` | once handled |

Prefer APIs that unregister themselves:

- `DefaultLifecycleObserver` attached to a `LifecycleOwner`.
- `OnBackPressedDispatcher.addCallback(lifecycleOwner, callback)` (the owner-less overload never removes it).
- A `callbackFlow` with `awaitClose { unregister() }`, collected with `repeatOnLifecycle` or `collectAsStateWithLifecycle`.

In Compose:

```kotlin
val context = LocalContext.current
DisposableEffect(context) {
    val receiver = BatteryReceiver(onChange)
    ContextCompat.registerReceiver(context, receiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        ContextCompat.RECEIVER_NOT_EXPORTED)
    onDispose { context.unregisterReceiver(receiver) }
}
```

A lambda captured into a singleton from a composable (`Tracker.onEvent = { … }`) captures the composition's state and the Activity context through `LocalContext`. Hand it a scoped callback that's removed in `onDispose`.

## Fragments

A Fragment on the back stack keeps its instance but destroys its view. Anything that references the old view leaks it until the Fragment itself goes.

```kotlin
private var _binding: FragmentFeedBinding? = null
private val binding get() = _binding!!

override fun onDestroyView() {
    super.onDestroyView()
    binding.list.adapter = null   // the adapter can hold the RecyclerView
    _binding = null
}
```

- Collect flows with `viewLifecycleOwner.lifecycleScope` / `viewLifecycleOwner.repeatOnLifecycle`, not the Fragment's own `lifecycleScope`.
- Observe LiveData with `viewLifecycleOwner`.
- New screens should be Compose (`xml-to-compose-migration-pro`), which removes this class of leak.

## Handlers, threads, and inner classes

- An anonymous `Runnable` posted with `postDelayed` holds the Activity until it runs. A non-static inner class holds its outer instance.
- Replace with a coroutine in `lifecycleScope` (cancelled on destroy) or `viewModelScope`.
- A raw `Thread` or executor task that captures the Activity leaks it for as long as it runs. `GlobalScope` does the same (`android-coroutines-best-practices.md`).

## Services and work

- A started service runs until `stopSelf()` / `stopService()`. A service that's never stopped keeps the process alive and everything it holds in memory.
- Bound services unbind in the matching callback.
- For deferrable work, WorkManager instead of a long-running service.

## WebView

- A `WebView` holds a large native footprint. Create it per screen, call `destroy()` after removing it from the hierarchy, and never keep one in a static field to "speed up" the next screen.

## Leaks that aren't yours

LeakCanary flags some framework and OEM leaks as "library leaks". Note them, don't spend time on them, unless they're on a common flow and a workaround exists.
