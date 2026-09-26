---
description: Adaptive layout for resizable iOS apps and iPhone Duo — size classes over idiom, the iOS 27 resizability default, the UIScene mandate, ArrangementView and hinge APIs, reserved regions, vertical toolbars, fold continuity, and simulator testing
globs: "**/*.{swift,h,m,mm}"
---

# Apple Adaptive Layout (Resizable Apps & iPhone Duo)

**Building against the iOS 27 SDK opts your app into resizability.** Adaptive layout is no longer an iPad refinement — it's the platform default on iPhone too, and iPhone Duo (Apple's book-style foldable: 5.4″ outer display, 7.6″ inner) makes a fixed-size assumption visible on a phone. Two hard consequences before any styling question:

- **The UIScene lifecycle is mandatory.** An app still using only the legacy app lifecycle **will not launch** when built with the latest SDKs. Migrate to `UIScene` first; nothing below matters until it launches.
- **`UIRequiresFullScreen` no longer opts you out.** On iPhone under iOS 27 it's honored as *discrete* resizing — the system transitions the scene to a new configuration matching each size, honoring your supported orientations. It's a rendering-quality escape hatch for games, not a way to stay fixed-size.

> **Toolchain.** iPhone Duo support ships in the **iOS 27.1 SDK / Xcode 27.1** (Apple silicon, macOS Tahoe 26.6+ — the minimum rises across 27.x point releases, so check the release notes for the version you pin). The 27.1 APIs below (`ArrangementView`, `onHingeChange`, reserved regions, toolbar axis behavior) are new; App Store Connect accepts TestFlight builds made with the 27.1 SDK. Verify spellings against the SDK you actually build against — beta symbols can still shift.

## Branch on Space, Never on Device

- **Size classes are the primary tool.** SwiftUI `@Environment(\.horizontalSizeClass)` / `\.verticalSizeClass`; UIKit `traitCollection.horizontalSizeClass` / `.verticalSizeClass`.
- **The user-interface idiom is no longer meaningful for layout.** `UIDevice.current.userInterfaceIdiom == .pad` tells you nothing about available space — Duo's inner display reports **regular width *and* regular height** (so sidebars are appropriate) while still being an iPhone. Apps are expected to use the space they're given regardless of idiom.
- **Never branch on interface orientation.** The inner display does not honor `supportedInterfaceOrientations` for resizable apps. Orientation is an output of window shape, not an input to layout.
- **Never read `UIScreen.main`** — ambiguous on a two-display device and deprecated. Get the screen from the scene: `window?.windowScene?.screen`; for scale use `traitCollection.displayScale`.
- Prefer **local view/scene geometry** (`GeometryReader`, `containerRelativeFrame()`, the view's own `bounds`) over anything global.

```swift
// ❌ Idiom + orientation — both wrong on Duo, iPad multitasking, and Mac Catalyst
if UIDevice.current.userInterfaceIdiom == .pad { showSidebar() }

// ✅ Branch on the space you actually have
@Environment(\.horizontalSizeClass) private var horizontalSizeClass
var showsSidebar: Bool { horizontalSizeClass == .regular }
```

## Let the System Containers Adapt

Reach for these before hand-rolling conditionals — they already handle folded/unfolded, split view, and free resize: `NavigationSplitView` / `UISplitViewController`, `TabView` / `UITabBarController`, sheets, popovers, context menus, alerts.

- **`ViewThatFits`** is the cheap win for one-off orientation flips — it picks the first child that fits instead of you branching:

  ```swift
  ViewThatFits(in: .horizontal) {
      HStack { Detail(); Sidebar() }   // preferred when there's room
      VStack { Detail(); Sidebar() }   // fallback when there isn't
  }
  ```

- **Sidebar placement on a large inner display:** `TabView { … }.defaultTabBarPlacement(.sidebar)` (SwiftUI) / `tabBarController.sidebar.preferredPlacement = .sidebar` (UIKit).
- **Standalone UIKit bars don't adapt.** A bare `UIToolbar` / `UINavigationBar` outside a navigation or tab container won't get the system's vertical-bar and edge-to-edge treatment — host it in the container instead.

## Arrangements — Two Views Around the Fold (iOS 27.1)

When two views should coexist across the hinge, use `ArrangementView` rather than a hand-built conditional:

```swift
ArrangementView {
    VideoPlayer(player: player)          // primary — top half in tabletop pose
} secondary: {
    PlaybackControls(player: player)     // secondary — bottom half, off the fold
}
.arrangementViewStyle(.split)            // .split keeps both visible; .overlay stacks
```

- **`.split`** (the default) divides the bounds and keeps both regions unobscured. **`.overlay`** floats the secondary over the primary — a foreground/background relationship.
- **UIKit:** `UIArrangementViewController` as the **root view controller of your `UINavigationController`**, configured with primary and secondary view controllers.
- **Arrangements are layout, not navigation.** Don't nest navigation containers *inside* one, and don't embed an arrangement in a `List` or scroll view.
- **Don't re-derive the split from the hinge angle.** The arrangement already adapts around available space *and* the fold — that's the whole point.
- Prefer `NavigationSplitView` when the relationship is list→detail with selection and back behavior; `ArrangementView` is for two co-resident views.

## The Hinge — Enhancement Only

```swift
.onHingeChange { _, context in
    // `context.hinge` is OPTIONAL — most displays have no hinge at all.
    if let hinge = context.hinge, hinge.status == .partiallyOpen {
        foldEffect = min(max(hinge.angle.degrees / 180, 0), 1)
    } else {
        foldEffect = 0
    }
}
```

- **`context.hinge` is optional** — every non-folding device, and the Duo's own outer display, has none. Code that force-unwraps it is broken on the entire rest of the lineup.
- **Never drive layout from the raw hinge angle.** Use size classes and arrangements for structure; spend the angle on *optional* polish — Apple's own "unfold effect" animates the outer display into feeling like a window onto the inner one.
- `hinge.status` gives the coarse state; `hinge.angle.degrees` the continuous value. Treat status as a layout-adjacent signal and the angle purely as animation input — layouts that snap per degree read as jitter.
- **Spend posture code where it pays**: camera, video, and media playback benefit from the tabletop stand. A settings screen needs no hinge code; posture-reactive layout everywhere is over-engineering.

## Reserved Regions — Ask, Don't Infer (iOS 27.1)

The fold and system UI claim space. Query it instead of computing it:

```swift
GeometryReader { proxy in
    let divisions  = proxy.reservedRegions(kind: .division)   // the fold splitting content
    let occlusions = proxy.reservedRegions(kind: .occlusion)  // hardware/system UI covering it
    // Each region exposes .frame, .margins, and .isActive.
}
```

- **`.division`** = the display is logically split (content shouldn't straddle it). **`.occlusion`** = something covers part of the display.
- Check **`.isActive`** — regions exist but aren't always in effect; pass `.includeInactive` only when you deliberately want to plan for a region that isn't currently applied.
- **Never let an interactive control land in a division or occlusion.** A custom layout that partially closes can otherwise put a button *underneath the fold* — unreachable, and invisible in a screenshot test.

## Vertical Toolbars (iOS 27.1)

On the inner display the system may lay toolbars out vertically. System containers do this for you; override per item only when an item genuinely can't rotate:

- `.axisBehavior(.horizontalOnly)` forces horizontal; `.axisBehavior(.verticalPreferred)` opts in.
- Read `toolbarVerticalEdge` from the environment when content must know which edge it's on.
- `.toolbarVerticalBehavior(.disabled)` turns the system behavior off — a last resort, not a default.

## Folded ↔ Unfolded: Continuity Is the Requirement

**The single most important thing: the layout must survive every fold state *and the transitions between them* while state is live.** Opening or closing the device re-flows the layout under a running app — it is a configuration change, not a relaunch.

What must survive a fold, an unfold, and an outer↔inner display switch:

- **Navigation depth and selection** — a screen three levels deep stays three levels deep; the selected row stays selected. On unfold, a pushed detail should *become* the detail pane of a split/arrangement — not pop back to the list. Custom navigation usually gets this wrong; test it explicitly.
- **Text entry and first responder** — in-progress input and cursor position, including inside presented sheets.
- **Scroll position** and list offset.
- **Media playback** position and state.
- **In-flight work** — a running upload or request must not restart.
- **Session identity** — snapping shut mid-task moves the UI to the outer display; the user's session must not reset.
- **Visual stability** — navigation shouldn't visibly jump or re-animate. Interrupted animations and layout jumps are the tell that a transition is rebuilding instead of updating.

Where it breaks:

- **SwiftUI**: `@State` on a view that gets *replaced* when the layout branch flips loses its value. Hoist it above the branch, or key it to content identity rather than layout shape. Use `@SceneStorage` / an observable model for anything that must outlive re-composition.
- **UIKit**: update the existing hierarchy in `traitCollectionDidChange` / `viewWillTransition(to:with:)` — rebuilding it drops first-responder status and scroll offsets.
- **Anything cached from the old geometry** — a stored `isCompact`, a computed column count, a frame captured once — is stale the moment the device folds.
- **Fixed frames** clip content as the window narrows; that's the most common visible symptom.

## Testing

**Simulator (Xcode 27.1).** Install the iOS 27.1 runtime via Settings ▸ Components, then pick iPhone Duo as a normal build destination. Toolbar buttons at the bottom fold and unfold it; **hold ⌥ Option to get a slider for precise hinge angles**. Device Hub (Xcode 27) also resizes a running app by dragging its edges, and Xcode Previews gained the same resize mode plus a Display group for previewing on an alternative display.

**The test recipe that actually finds bugs**: navigate several screens deep, open a sheet, start typing — *then* fold and unfold while it's all live. Repeat in both directions and in each orientation. Add split view and free resize.

**What the simulator can't tell you** — budget physical-device time for: camera transitions between outer / inner / rear cameras, one-handed reachability in partially folded poses, haptics, thermal behavior, and how the fold actually looks.

## Common Pitfalls

- **Legacy app lifecycle** — doesn't launch at all against the latest SDK. Migrate to `UIScene`.
- **`UIRequiresFullScreen` treated as an opt-out** — it isn't one anymore; it selects discrete resizing.
- **Idiom or orientation checks driving layout** — wrong on Duo, iPad multitasking, and Mac Catalyst. Use size classes.
- **`UIScreen.main`** anywhere — use the window scene's screen.
- **Force-unwrapping `context.hinge`** — most devices have no hinge, including Duo's outer display.
- **Driving layout from the hinge angle** — structure comes from size classes and arrangements; the angle is animation polish.
- **Computing the fold's position instead of querying `reservedRegions`** — and shipping a control underneath it.
- **Symmetric safe-area math** (`- insets.left * 2`) — inset the rect instead: `view.bounds.inset(by: view.safeAreaInsets)`.
- **Hardcoded sizes, aspect ratios, or corner radii** — multiple display shapes now, and the window is not the display. Use `ConcentricRectangle()` / `UICornerConfiguration` for corners.
- **State lost, animations interrupted, or navigation jumping on fold** — the transition is rebuilding instead of updating.
- **Navigation containers inside an `ArrangementView`**, or an arrangement inside a `List` / scroll view.
- **Shipping without physical-device testing** of camera, reachability, and haptics — the simulator covers none of them.
