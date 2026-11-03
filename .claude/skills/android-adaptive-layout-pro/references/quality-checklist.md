# Configuration, input, and quality-tier readiness

The manifest and input layers decide whether an adaptive layout ever gets the chance to run.

## Manifest and the Android 16/17 changes

- **Apps targeting Android 16 (API 36) and later: `screenOrientation`, `minAspectRatio` / `maxAspectRatio`, `resizeableActivity="false"`, and `setRequestedOrientation()` are ignored on screens with smallest width ≥ 600dp** (tablets, unfolded foldables, desktop windows, external displays). Ignored orientation values: `portrait`, `reversePortrait`, `sensorPortrait`, `userPortrait`, and the four landscape equivalents. The app fills the window, without pillarboxing.
- **Exemptions are narrow**: games (`android:appCategory="game"`), screens below sw600dp, and users who choose the app's default in the system aspect-ratio settings. Business apps have no exemption path.
- **Desktop windowing ignores locks already**: an orientation-locked app is freely resizable there, and a non-resizable one is scaled with its aspect ratio kept.

Audit every `<activity>`:
  - `android:screenOrientation="portrait"` / `"sensorPortrait"` — the layout that relied on it now renders landscape on tablets. Finding: remove the lock AND verify the layout adapts.
  - `android:resizeableActivity="false"`, `android:maxAspectRatio` / `minAspectRatio` — same treatment.
  - `setRequestedOrientation()` / `requestedOrientation =` in code — same treatment; it's ignored on large screens too.
  - `PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY` opt-out present → **Android 17 (API 37) removed it**. Flag it as broken the moment the app targets 37, and as a deadline before then.
- Genuinely orientation-bound non-game content keeps working on compact screens; on large screens it must handle both orientations. Games declare `android:appCategory="game"` rather than relying on the opt-out.
- Test the API 37 behavior before raising targetSdk by enabling the `UNIVERSAL_RESIZABLE_BY_DEFAULT` compat flag (developer options ▸ app compatibility changes, or `adb shell am compat enable UNIVERSAL_RESIZABLE_BY_DEFAULT <package>`).
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

- **Keyboard**: physical ↔ virtual keyboard switch without relaunch (Tier 3 `Keyboard_Input`); focus visibility and Tab/arrow order (shared with accessibility — defer the semantics audit to `android-accessibility-pro`); shortcuts for common actions published through the Keyboard Shortcuts Helper (`Activity.onProvideKeyboardShortcuts`), handled with `Modifier.onPreviewKeyEvent` / `onKeyEvent`; Enter sends in messaging, Esc closes dialogs/menus and clears search, Space plays/pauses media (Tier 2 `Keyboard_*`).
- **Mouse / trackpad**: click, select, and scroll everywhere (Tier 3 `Mouse_Trackpad_Basic`); hover states (`Modifier.hoverable` + indication); right-click → context menu next to the item (`Modifier.pointerInput` detecting the secondary button); scroll wheel on horizontal lists; contextual pointer icons (`Modifier.pointerHoverIcon`) on resize handles and text.
- **Stylus**: basic stylus input works like touch with no code; Android 14+ supports stylus handwriting in `EditText` and Compose text fields. Drawing surfaces add pressure/tilt (`PointerType.Stylus`), palm rejection, and low-latency ink (`androidx.ink`).
- **Drag and drop**: `Modifier.dragAndDropSource` / `dragAndDropTarget` for content users would naturally move between apps in multi-window (images, text, files). Cross-instance and drop-to-open-window flags are in `multi-window-and-desktop.md`.

## Play adaptive app quality tiers

Google's [adaptive app quality guidelines](https://developer.android.com/docs/quality-guidelines/adaptive-app-quality) are the external bar; Play badges and features optimized apps (including Googlebook's desktop badging). Each guideline has an ID; cite it in findings. Not every app needs every item, only those that fit its use cases.

- **Tier 3 — Adaptive ready**: fills the screen or window, not letterboxed or in compatibility mode (`Config_Changes`); state survives rotation, fold, resize, minimize/maximize, and *combinations* of them (`Config_Combinations`); fully functional in multi-window with multi-resume (`Multi-Window_Functionality`, `Multi-Resume`); camera preview and media projection correct in every orientation and fold state (`Camera_Preview`, `Media_Projection`); keyboard, basic mouse/trackpad, and basic stylus input.
- **Tier 2 — Adaptive optimized**: size-class layouts and multi-pane where useful, activity embedding for View-based apps (`Responsive_adaptive_layouts`); secondary elements not stretched (`UI_Secondary_Elements`); 48dp targets; focus states on custom drawables; keyboard navigation, shortcuts, Enter/Esc/Space behaviors; right-click context menus; content zoom.
- **Tier 1 — Adaptive differentiated**: an experience designed for the device: multitasking and multi-instance, foldable postures, drag and drop, advanced stylus.

## Testing per size class

- AVDs: Pixel Fold (outer, inner, half-opened), Medium Tablet (landscape + portrait), Desktop (Preview; needs Android Studio canary), and the resizable emulator. Split-screen and desktop windowing on each; minimize/maximize/restore on desktop.
- Google's reference sizes: foldable 841×701dp, 8" tablet 1024×640dp, 10.5" tablet 1280×800dp, 13" Chromebook 1600×900dp, and Googlebook (160 ppi).
- Compose tests: `DeviceConfigurationOverride.ForcedSize(DpSize(…))` per canonical layout; screenshot tests at compact/medium/expanded (+ large if `BREAKPOINTS_V2`).
- Manual: rotate, fold, split, resize, external keyboard + mouse — one pass per release on the screens the audit flagged.

## Audit sequence

1. Manifest: list every `<activity>` with orientation/resizability restrictions; check `targetSdk`.
2. Grep for display-metrics usage in layout math.
3. Camera/media screens: orientation handling.
4. Interactive content: hover / right-click / keyboard shortcut / drag-and-drop presence.
5. Map results onto the quality tiers by guideline ID; state which tier the app currently meets.
