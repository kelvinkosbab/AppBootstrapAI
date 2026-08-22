# Foldables — posture, display switches, state survival

A foldable is two size classes in one device plus a hinge. Most foldable bugs are ordinary configuration-change bugs made visible.

## Observing the fold

```kotlin
// At the screen root (or an Activity-scoped holder), not in leaf composables:
val layoutInfo by WindowInfoTracker.getOrCreate(context)
    .windowLayoutInfo(activity)
    .collectAsStateWithLifecycle(initialValue = null)
val fold = layoutInfo?.displayFeatures?.filterIsInstance<FoldingFeature>()?.firstOrNull()
```

- `FoldingFeature.state`: `FLAT` (fully open — treat as a plain large window) or `HALF_OPENED` (posture matters).
- `orientation`: `HORIZONTAL` hinge → **tabletop** posture; `VERTICAL` hinge → **book** posture.
- `occlusionType == FULL` → the hinge hides content; keep controls and text off `bounds`.
- `isSeparating` → the hinge splits the window into two logical areas — the signal to use a two-pane layout split at `bounds`.

Findings: polling `Configuration` for fold state (there is none — only `FoldingFeature`); reading the tracker in multiple places; assuming a foldable is always `FLAT`.

## Posture layouts

- **Tabletop** (half-opened, horizontal hinge — laptop-like): content in the top half (video, viewfinder, map), controls in the bottom half. Video players and camera apps that ignore this put the controls under the user's fingers *and* across the hinge.
- **Book** (half-opened, vertical hinge): two panes split at the hinge — list | detail, reader | notes. Never place a single centered element across the crease.
- Only react to posture when the experience genuinely benefits (media, camera, reading); a settings screen doesn't need tabletop mode. Flag over-engineering too.

## Inner ↔ outer display switch

- Unfolding moves the app from a compact outer display to a medium/expanded inner one **mid-session**. The size class read at the root updates; anything cached at first composition (a `remember`ed `isCompact`, a device-type decision) doesn't. Flag `remember { windowSizeClass... }` without keys.
- Navigation state must carry over: a detail screen open on the outer display should become the detail pane of list-detail on the inner display — `NavigableListDetailPaneScaffold` handles this; custom navigation usually pops back to the list (finding).
- Continuity applies in reverse: folding should not lose the current item.

## Fold/unfold is a configuration change

- Unless the Activity declares `android:configChanges` for the relevant changes (it usually shouldn't in Compose apps), the Activity recreates. Audit for state that won't survive:
  - User input in `remember { mutableStateOf("") }` → `rememberSaveable` or ViewModel.
  - Scroll position: `rememberLazyListState()` is saveable; custom `ScrollableState` wrappers often aren't.
  - In-flight work started from the composable (`LaunchedEffect` doing a network call that restarts on recreation) → move to the ViewModel.
  - Media playback position, camera session, Bluetooth connection → retained holder / foreground service, not the Activity.
- Multi-resume: in multi-window, a foldable can have two resumed Activities — don't assume `onResume` means "the only visible app" (camera/audio focus logic).

## Testing

- Pixel Fold AVD: fold/unfold via the emulator's posture controls; test with the app on the outer display first, then unfold. Check the inner display's *both* orientations.
- `DeviceConfigurationOverride.ForcedSize` in Compose tests exercises the size-class branches; posture needs the emulator (or `FoldingFeature` fakes via `WindowLayoutInfoPublisherRule` from `window-testing`).

## Audit sequence

1. Find the `WindowInfoTracker` observation (or note its absence where posture matters).
2. For media/camera/reader screens: is there a tabletop/book response? For everything else: is there *unnecessary* posture code?
3. Trace state across Activity recreation for every screen (input, scroll, selection, in-flight work).
4. Walk the outer→inner navigation continuity path.
