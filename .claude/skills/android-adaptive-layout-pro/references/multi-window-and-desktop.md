# Multi-Window, Multi-Instance, and Desktop Windows

Split screen, free-form desktop windowing on tablets, connected external displays, and Googlebook laptops all put the app in a window that can be resized, minimized, moved to another display, or opened twice. None of this needs a special device to break an app: a phone plugged into a monitor is enough. This reference covers what changes when the window is no longer the screen.

## Multi-window and multi-resume

- **Resumed is not focused.** In multi-window, every visible activity is resumed; only one has focus. Don't pause playback, stop location updates, or freeze live data in `onPause` for a visible window. Use `onStop` for "no longer visible" work, and `onTopResumedActivityChanged(isTopResumed)` only for things that truly need focus (exclusive camera access).
- **Shared exclusive resources.** Another visible app can take the camera or microphone. Handle `CameraDevice.StateCallback.onDisconnected` / CameraX unbinding by showing a "camera in use" state, and reclaim when the window regains top-resumed.
- **Picture-in-picture** for video: `setPictureInPictureParams(... setAutoEnterEnabled(true))` so leaving the app keeps playback visible.

Findings: `onPause` that stops media or polling; camera code that crashes or shows black when another app holds the camera.

## Multi-instance

Apps where two windows help (documents, chats, browsers, email) should let users open one:

```xml
<application ...>
    <property
        android:name="android.window.PROPERTY_SUPPORTS_MULTI_INSTANCE_SYSTEM_UI"
        android:value="true" />
</application>
```

- With the property, the system shows "New window" in the app's menus on desktop and the taskbar. Open a second window yourself with `Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK` (and `FLAG_ACTIVITY_LAUNCH_ADJACENT` to place it next to the current one in split screen).
- **Per-window state lives in that window's ViewModel / `SavedStateHandle`.** A `@Singleton` holding "the current document" or "the selected chat" makes both windows show the same thing.
- Shared data (repositories, the database) stays singleton and is observed as `Flow`, so an edit in one window shows up in the other.

Findings: `launchMode="singleInstance"` / `singleTask` on a document activity that users would open twice; singletons holding screen state.

## Desktop windowing

Desktop windowing runs on tablets (Android 16 QPR and later), connected displays, and Googlebook. Every window is freely resizable and has a caption bar.

- **Orientation and resizability locks are ignored here, whatever the targetSdk.** An orientation-locked app is resizable; a `resizeableActivity="false"` app is scaled with its aspect ratio kept, which looks blurry. Fix the layout instead.
- **Caption bar.** Content must not sit under it: pad with `WindowInsets.captionBar` (Compose: `Modifier.windowInsetsPadding(WindowInsets.captionBar)`, or `safeDrawing`, which includes it). To draw a custom header into it, set `WindowInsetsController.APPEARANCE_TRANSPARENT_CAPTION_BAR_BACKGROUND`, keep clear of the system buttons reported by `WindowInsets.getBoundingRects(WindowInsets.Type.captionBar())`, and call `View.setSystemGestureExclusionRects()` for custom controls inside it so taps aren't taken as window drags.
- **Initial size and full screen.** `ActivityOptions.setLaunchBounds()` suggests a size for a new window; `Activity.requestFullScreenMode()` lets a player or game go full screen from desktop. Don't fight the user's chosen size.
- **Window lifecycle.** Minimize, maximize, restore, and drag-resize are configuration changes. State must survive each one and their combinations (Play `Config_Combinations`).

## Connected displays

- **The display changes under the app.** Moving a window to an external monitor changes `Display`, density, and possibly the size class and HDR support.
- **Use the activity context** (or Compose `LocalConfiguration`, `LocalDensity`, `LocalWindowInfo`) for anything about the window or display. `applicationContext.resources.displayMetrics` and `WindowManager.defaultDisplay` describe the built-in display, not where the window is.
- **No device allowlists.** `Build.MODEL` checks and built-in screen size checks never fire on a phone driving a monitor. Branch on the window.
- **Handle display changes** with `onConfigurationChanged` / recomposition, or let the activity recreate. Don't cache density or dimensions at startup.

Findings: `applicationContext` display math, `defaultDisplay`, cached `displayMetrics`, `Build.MODEL` gates.

## Desktop vs touch interaction

Decide how dense the UI is from how the user is interacting, not from the device:

- **Stable today:** size classes for structure, plus first-class mouse and keyboard support (hover, right-click, shortcuts, scroll in both directions, pointer icons).
- **Coming:** WindowManager 1.6 (alpha) `WindowInfoTracker.windowEngagementInfo()` reports `EngagementMode.PRECISE_POINTER` vs touch; Compose's experimental `mediaQuery { pointerPrecision == … }` and `keyboardKind` (behind `ComposeUiFlags.isMediaQueryIntegrationEnabled`) express the same in UI code. Recommend them only behind the project's experimental-API policy, and don't flag their absence as a defect.

## Drag and drop between windows

- Compose: `Modifier.dragAndDropSource { … }` and `Modifier.dragAndDropTarget(shouldStartDragAndDrop = …, target = …)`.
- Views: `View.startDragAndDrop()` with `DRAG_FLAG_GLOBAL` for other apps, `View.DRAG_FLAG_GLOBAL_SAME_APPLICATION` to drag between your own instances, and `DRAG_FLAG_START_INTENT_SENDER_ON_UNHANDLED_DRAG` to open a new window when content is dropped on empty desktop space.
- Call `activity.requestDragAndDropPermissions(event)` before reading a `content://` URI dropped from another app.

## Activity embedding (View-based apps)

For apps not yet on Compose layouts, activity embedding shows two activities side by side on large windows:

- Rules: `SplitPairRule` (list + detail), `SplitPlaceholderRule` (empty detail), `ActivityRule` (always expanded), declared in XML or created with `RuleController`.
- `SplitAttributesCalculator` adapts the split to window size and fold posture; `ActivityEmbeddingController.isActivityEmbedded()` tells an activity it's in a split.
- WindowManager 1.5: `EmbeddingConfiguration(isAutoSaveEmbeddingState = true)` restores splits after process death.

Prefer Compose canonical layouts for new code; activity embedding is the bridge for existing multi-activity apps.

## Audit Steps

1. Grep `onPause` for media, camera, and polling teardown; check for `onTopResumedActivityChanged` where focus matters.
2. Check the manifest for `PROPERTY_SUPPORTS_MULTI_INSTANCE_SYSTEM_UI` and `launchMode` on document-style activities; grep `@Singleton` holders for per-screen state.
3. Grep `captionBar`, `windowInsetsPadding`, `safeDrawing` near top-level scaffolds; check custom headers for gesture-exclusion rects.
4. Grep `applicationContext` near `displayMetrics` / `resources`, `defaultDisplay`, `Build.MODEL`.
5. Grep `dragAndDropSource` / `startDragAndDrop` and the permission request for cross-app drops.
6. Run on the Desktop and resizable emulators: open two windows, minimize/maximize/restore, move a window to a second display, and drag content between windows.
