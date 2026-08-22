# Configuration, input, and quality-tier readiness

The manifest and input layers decide whether an adaptive layout ever gets the chance to run.

## Manifest and the Android 16 change

- **Apps targeting Android 16 (API 36): `screenOrientation`, aspect-ratio limits, and `resizeableActivity="false"` are ignored on screens ≥ 600dp** (tablets, unfolded foldables, desktop windows). Audit every `<activity>`:
  - `android:screenOrientation="portrait"` / `"sensorPortrait"` — the layout that relied on it now renders landscape on tablets. Finding: remove the lock AND verify the layout adapts.
  - `android:resizeableActivity="false"`, `android:maxAspectRatio` / `minAspectRatio` — same treatment.
  - `PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY` opt-out present → temporary by design (removed at targetSdk 37); flag as tech debt with a removal date.
- Genuinely orientation-bound content (a landscape-only game) keeps working on compact screens; on large screens it must handle both — there is no exemption path beyond API 36.
- `android:configChanges` declaring `orientation|screenSize|smallestScreenSize|screenLayout` to *avoid* recreation: acceptable only if every `onConfigurationChanged` path re-lays-out; in Compose apps it's usually a smell hiding state bugs.

## Window ≠ display

- `Resources.displayMetrics` / `DisplayMetrics.widthPixels` describe the **display**; in multi-window and desktop mode the **window** is smaller. Layout math on display metrics overflows the window. Use `LocalWindowInfo` / `currentWindowSize()` / the size class.
- `WindowManager.defaultDisplay` is deprecated; `Activity.windowManager.currentWindowMetrics` gives the window bounds.
- Insets: free-form windows have caption bars; `WindowInsets.safeDrawing` handling must not assume a phone status bar shape.

## Camera and media

- Camera preview orientation must follow the display rotation *and* the sensor orientation (`CameraX` handles it when given the `Display`/`Surface` correctly; manual `Camera2` math assuming portrait is the classic stretched-preview bug on tablets).
- Video: tabletop posture (see `foldables.md`); picture-in-picture on large screens; don't force landscape for playback.

## Large-screen input

Tablets and desktop windows bring hardware input. Each item is a degraded-tier finding when absent on interactive content:

- **Keyboard**: focus visibility and Tab order (shared with accessibility — defer the semantics audit to `android-accessibility-pro`), keyboard shortcuts for primary actions (`Modifier.onPreviewKeyEvent` / menu-provided shortcuts), Enter to submit forms.
- **Mouse / trackpad**: hover states (`Modifier.hoverable` + indication), right-click → context menu (`Modifier.pointerInput` detecting secondary button), scroll wheel on horizontal lists.
- **Stylus**: pressure/tilt for drawing surfaces (`PointerType.Stylus`), palm rejection, low-latency ink (`androidx.ink`) where drawing is core.
- **Drag and drop**: `Modifier.dragAndDropSource` / `dragAndDropTarget` for content users would naturally move between apps in multi-window (images, text, files).

## Play large-screen quality tiers

Google's tiered checklist (Tier 3 basic → Tier 1 differentiated) is the external bar; Play surfaces tablet quality in listings and may rank against it. Map findings to it:

- **Tier 3 (basic)**: no orientation locks, layouts fill the window without stretching, state survives rotation/fold, keyboard/mouse basics work.
- **Tier 2 (better)**: canonical layouts per size class, multi-window/free-form support, hover/right-click/stylus, drag and drop.
- **Tier 1 (best)**: posture-aware experiences, desktop-class features (keyboard shortcuts everywhere, window-size-tuned density).

## Testing per size class

- AVDs: Pixel Tablet (landscape + portrait), Pixel Fold (outer, inner, half-opened), resizable emulator (free-form), split-screen on each.
- Compose tests: `DeviceConfigurationOverride.ForcedSize(DpSize(…))` per canonical layout; screenshot tests at compact/medium/expanded (+ large if `BREAKPOINTS_V2`).
- Manual: rotate, fold, split, resize, external keyboard + mouse — one pass per release on the screens the audit flagged.

## Audit sequence

1. Manifest: list every `<activity>` with orientation/resizability restrictions; check `targetSdk`.
2. Grep for display-metrics usage in layout math.
3. Camera/media screens: orientation handling.
4. Interactive content: hover / right-click / keyboard shortcut / drag-and-drop presence.
5. Map results onto the quality tiers; state which tier the app currently meets.
