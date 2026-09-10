---
description: Adaptive layout for resizable iOS apps and iPhone Duo — size classes over idiom, the iOS 27 resizability default, the UIScene mandate, arrangements and hinge APIs, asymmetric safe areas, and Device Hub testing
globs: "**/*.{swift,h,m,mm}"
---

# Apple Adaptive Layout (Resizable Apps & iPhone Duo)

**Building against the iOS 27 SDK opts your app into resizability.** Adaptive layout is no longer a refinement for iPad — it is the platform default on iPhone too, and iPhone Duo (Apple's book-style foldable: 5.4″ outer display, 7.6″ inner) makes a fixed-size assumption visible on a phone. Two hard consequences before any styling question:

- **The UIScene lifecycle is mandatory.** An app still using only the legacy app lifecycle **will not launch** when built with the latest SDKs. Migrate to `UIScene` first; nothing below matters until it launches.
- **`UIRequiresFullScreen` no longer opts you out.** On iPhone under iOS 27 it is honored as *discrete* resizing — the system transitions the scene to a new configuration matching each size, honoring your supported orientations. It is a rendering-quality escape hatch for games, not a way to stay fixed-size.

> **Version discipline.** Resizability-by-default and the scene mandate land with the **iOS 27 SDK**. `ArrangementView`, reserved regions, and edge-to-edge/vertical bar layout are **iOS 27.1**. These symbols are new — verify names against the SDK you're building with before hardcoding; the *patterns* are stable, the spellings can move.

## Branch on Space, Never on Device

- **Size classes are the primary tool.** SwiftUI `@Environment(\.horizontalSizeClass)` / `\.verticalSizeClass`; UIKit `traitCollection.horizontalSizeClass` / `.verticalSizeClass`.
- **The user-interface idiom is no longer meaningful for layout.** `UIDevice.current.userInterfaceIdiom == .pad` tells you nothing about available space — an iPhone Duo's inner display reports **regular width *and* regular height** (so sidebars are appropriate) while still being an iPhone. Apps are expected to use the space they're given regardless of idiom.
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

These already do the right thing across folded/unfolded, split view, and resize — reach for them before hand-rolling conditionals: `NavigationSplitView` / `UISplitViewController`, `TabView` / `UITabBarController`, sheets, popovers, context menus, alerts.

- **Sidebar placement on a large inner display:** `TabView { … }.defaultTabBarPlacement(.sidebar)` (SwiftUI) / `tabBarController.sidebar.preferredPlacement = .sidebar` (UIKit).
- **Standalone UIKit bars don't adapt.** A bare `UIToolbar`/`UINavigationBar` outside a navigation or tab container won't get the system's vertical-bar and edge-to-edge treatment — host it in the container instead.

## Arrangements — Two Views Around the Fold (iOS 27.1)

When two views should coexist across the hinge, use the arrangement containers rather than a hand-built `HStack`/`VStack` conditional:

- **SwiftUI:** `ArrangementView` with a primary and secondary view, placed inside a `NavigationStack`.
- **UIKit:** `UIArrangementViewController` as the root view controller of your `UINavigationController`, configured with primary and secondary view controllers.
- **Styles:** **split** (the default — divides bounds; use when both views must stay unobscured) or **overlay** (foreground/background relationship).

Constraints that bite:

- **Arrangements provide layout, not navigation.** Don't put navigation containers *inside* one, and don't embed an arrangement inside a `List` or scroll view.
- They adapt around available space *and* the fold — that's the point. Don't re-implement the split by reading the hinge yourself.

## Poses & the Hinge

- Read hinge state with `onHingeChange` (SwiftUI) or `UIHingeInteraction` (UIKit): a coarse status (**closed / partially open / fully open**) plus a continuous angle.
- **React to posture only where it earns its place** — a half-open device is a stand, which matters for camera, video, and media playback. A settings screen needs no hinge code; posture-reactive layout everywhere is over-engineering.
- **Ask the geometry what's obstructed** instead of inferring it: reserved regions (`ReservedRegion` in SwiftUI, `UIViewReservedRegion` in UIKit; `reservedRegion` on `GeometryProxy` / `UIView`, iOS 27.1+) let custom UI claim space without colliding with system UI or the fold.
- **Continuity is the requirement.** Opening or closing the device must preserve what the user was doing — selection, scroll position, text entry, playback. Treat every fold as a size change your state must survive: state belongs in a model/`@State` that outlives the layout branch, never in a value derived from the old size.

## Safe Areas Are Asymmetric

Insets differ per side and per display — the single most common source of "it's off-center on Duo":

```swift
// ❌ Assumes symmetry
let width = view.bounds.width - view.safeAreaInsets.left * 2

// ✅ Inset the rect and measure that
let width = view.bounds.inset(by: view.safeAreaInsets).width
```

- UIKit: align foreground content with `view.bounds.inset(by: view.safeAreaInsets)`; let backgrounds extend underneath.
- SwiftUI: `.ignoresSafeArea()` on the *background* only — never on content the user must reach.
- **Match the screen's corners** with `ConcentricRectangle()` (SwiftUI) / `UICornerConfiguration` (UIKit, iOS 26+) instead of hardcoding a corner radius that only looks right on one display.

## Camera on a Two-Display Device

Camera apps get extra surface and extra failure modes: use `CameraCaptureAccessory` for dual-display capture experiences, `AVCaptureDeviceDirectionCoordinator` for device-direction handling, and `RotationCoordinator` for preview orientation across display changes. A preview sized from a cached screen bounds is the classic stretched-viewfinder bug.

## Testing

- **Device Hub** (Xcode 27) replaces the separate Simulator and Devices & Simulators windows: rotate, screenshot, toggle dark mode, change font size, **resize freely by dragging edges**, and launch onto a connected device. **Xcode Previews gained the same resize mode** — exercise size classes without booting a simulator.
- The iPhone Duo simulator (Xcode 27.1+) has on-screen controls to open, close, rotate, and fold through the device's poses. Test every pose, plus split view and free resize.
- Xcode 27.1 ships an **"App Resizability"** coding-agent skill (renamed from "App Modernization") that finds and fixes common resizability issues in SwiftUI and UIKit — a useful first pass, but review its edits like any other agent output.
- Your app runs on iPhone Duo without recompiling; **screen usage improves with each SDK you build against** (iOS 27 extends content left of the status bar on the inner display; iOS 27.1 reaches the screen edge and adds vertical navigation/toolbar layout).

## Common Pitfalls

- **Legacy app lifecycle** — doesn't launch at all against the latest SDK. Migrate to `UIScene`.
- **`UIRequiresFullScreen` treated as an opt-out** — it isn't one anymore; it selects discrete resizing.
- **Idiom or orientation checks driving layout** — both are wrong on Duo, iPad multitasking, and Mac Catalyst. Use size classes.
- **`UIScreen.main`** anywhere — use the window scene's screen.
- **Symmetric safe-area math** (`- insets.left * 2`) — inset the rect instead.
- **Hardcoded sizes, aspect ratios, or corner radii** — multiple display shapes now, and the window is not the display.
- **State lost on fold/unfold** — a fold is a size change; selection, scroll, and input must survive it.
- **Navigation containers inside an `ArrangementView`**, or an arrangement inside a `List`/scroll view — arrangements are layout, not navigation.
- **Posture-reactive layout on screens that don't benefit** — hinge code has a cost; spend it on camera/media, not settings.
