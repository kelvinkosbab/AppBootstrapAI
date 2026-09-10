# iPhone Duo — arrangements, hinge, safe areas, continuity

iPhone Duo is a book-style foldable: a 5.4″ outer display that behaves like a standard iPhone, and a 7.6″ inner display that reports **regular width and regular height**. Most Duo bugs are ordinary resizability bugs made visible on a phone; a smaller set are genuinely fold-specific.

> **iOS 27.1 surface.** `ArrangementView` / `UIArrangementViewController`, reserved regions, and edge-to-edge/vertical-bar layout are new in 27.1. Verify symbol spellings against the SDK in use before flagging their absence as a finding.

## Arrangements — the two-view container

When two views should coexist across the hinge, the system container beats a hand-built conditional:

- **SwiftUI:** `ArrangementView` with a primary and a secondary view, placed inside a `NavigationStack`.
- **UIKit:** `UIArrangementViewController` as the **root view controller of your `UINavigationController`**, configured with primary and secondary view controllers.
- **Styles:** **split** — the default; divides its bounds between primary and secondary. Use when both must stay unobscured. **overlay** — for a foreground/background relationship.

Findings to raise:

- **Navigation containers nested inside an arrangement**, or an **arrangement embedded in a `List` or scroll view**. Arrangements provide *layout, not navigation*; both shapes are explicitly wrong.
- **A hand-rolled split that reads the hinge angle to place its divider** — the arrangement already adapts around available space *and* the fold. Re-deriving it is fragile and usually drops the overlay case.
- **`ArrangementView` used where `NavigationSplitView` is the better fit** — list+detail with selection and back behavior is the split view's job; arrangements are for two co-resident views, not a navigation hierarchy.

## Hinge & posture

Read posture with `onHingeChange` (SwiftUI) or `UIHingeInteraction` (UIKit): a coarse status (**closed / partially open / fully open**) plus a **continuous angle**.

- **Spend posture code where it pays**: camera viewfinders, video playback, and media controls benefit from a half-open "stand" posture (content up, controls down). Note its *absence* on those screens.
- **Flag posture code that doesn't earn its place** — hinge observation on a settings or list screen is complexity with no user benefit, and over-engineering is a finding in both directions.
- **Don't infer obstruction from the angle.** Ask the geometry: reserved regions (`ReservedRegion` in SwiftUI, `UIViewReservedRegion` in UIKit; `reservedRegion` on `GeometryProxy` / `UIView`) report where system UI or the fold claims space, so custom UI can avoid collisions without hardcoded math.
- Treat the coarse status as the layout signal and the continuous angle as an animation input — layouts that snap on every degree of angle change are jarring.

## Safe areas are asymmetric

Insets differ per side and per display. The canonical bug:

```swift
// ❌ Assumes symmetry — off-center on Duo and on any device with asymmetric insets
let width = view.bounds.width - view.safeAreaInsets.left * 2

// ✅ Inset the rect, then measure it
let width = view.bounds.inset(by: view.safeAreaInsets).width
```

- **UIKit**: align foreground content to `view.bounds.inset(by: view.safeAreaInsets)`; let backgrounds extend beneath.
- **SwiftUI**: `.ignoresSafeArea()` belongs on backgrounds only — never on content the user must reach or tap.
- **Corners**: `ConcentricRectangle()` (SwiftUI) / `UICornerConfiguration` (UIKit, iOS 26+) match the actual screen corner instead of a radius tuned for one display.
- Grep for `safeAreaInsets.left`, `.top`, `.bottom` used individually in arithmetic — each is a candidate.

## Camera on two displays

- `CameraCaptureAccessory` for dual-display capture experiences (preview on one display, controls or subject-facing preview on the other).
- `AVCaptureDeviceDirectionCoordinator` for device-direction handling as the device folds and rotates.
- `RotationCoordinator` for preview orientation across display changes.
- **The classic bug**: a preview layer sized from cached screen bounds or a fixed aspect ratio — stretched or letterboxed the moment the device unfolds. Any camera code reading `UIScreen.main.bounds` is broken-tier.

## Continuity across fold and resize

Opening or closing the device is a size change, and the user expects to keep what they were doing.

- **What must survive**: current selection, scroll position, text entry and cursor, sheet/popover presentation, media playback position, in-flight requests.
- **Where it breaks**: state derived from the *old* geometry (a cached column count, a stored `isCompact` computed once), view state that lives only in a branch that gets rebuilt, and UIKit controllers recreated on trait change instead of updated.
- **SwiftUI**: `@State` on a view that is replaced when the layout branch flips loses its value — hoist it above the branch, or key it to the content's identity rather than the layout shape. `@SceneStorage` / `@StateObject` for anything that must outlive re-composition.
- **UIKit**: prefer updating the existing hierarchy in `traitCollectionDidChange` / `viewWillTransition(to:with:)` over rebuilding it. Rebuilding drops first-responder status and scroll offsets.
- **Outer → inner continuity is the headline case**: a detail screen open on the folded display should become the detail pane of a split/arrangement when unfolded — not pop back to the list. Test that path explicitly; custom navigation usually gets it wrong.

## Audit sequence

1. Find two-view layouts → should they be an `ArrangementView` / `NavigationSplitView`? Check the nesting constraints.
2. Camera/media screens → posture handling present? Preview sized from geometry, not screen bounds?
3. Grep `safeAreaInsets.<edge>` in arithmetic → symmetric-math findings.
4. Trace state across a size change per screen: selection, scroll, text, playback, presentation.
5. Walk the folded→unfolded navigation path and name where continuity breaks.
