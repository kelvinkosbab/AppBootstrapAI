# Launch & resizability readiness

Audit this first. A layout finding is moot if the app doesn't launch, and the resizability posture determines whether every other finding is theoretical or shipping today.

## The UIScene mandate (launch-blocking)

Apps that still declare **only** the legacy app lifecycle **will not launch** when built against the latest SDKs. This is the highest-severity finding in the whole review.

What to check:

- `Info.plist` declares `UIApplicationSceneManifest` with at least one scene configuration.
- An `App`/`UISceneDelegate` (or SwiftUI `App` with `WindowGroup`) actually owns window setup — not `AppDelegate.window` assignment left over from the pre-scene era.
- Leftovers that signal a half-migration: `application(_:didFinishLaunchingWithOptions:)` creating a `UIWindow`, `UIApplication.shared.keyWindow` reads, `appDelegate.window` references across the codebase.
- SwiftUI apps are scene-based by construction — but a SwiftUI app wrapping a UIKit `AppDelegate` via `@UIApplicationDelegateAdaptor` can still carry legacy window code worth flagging.

## `UIRequiresFullScreen` is no longer an opt-out

Under iOS 27 on iPhone, `UIRequiresFullScreen` is honored as **discrete resizing**: on each size change the system transitions the scene to a new screen configuration matching that size, honoring supported orientations, so content renders at full quality in the space available.

- Its legitimate use is **rendering quality for games** and similar full-surface renderers — not "we don't want to adapt."
- If the key is present, the finding is usually *what it was protecting*: a layout that assumes one size. Report both.
- Don't recommend adding it to dodge adaptive work.

## SDK level determines how much screen you get

The app runs on iPhone Duo without recompiling, but the experience improves with the SDK you build against:

| Built against | Behavior |
|---|---|
| Pre-iOS 27 | Runs; conservative use of the inner display |
| **iOS 27** | **Resizable by default**; content extends left of the status bar on the inner display |
| **iOS 27.1** | Content reaches the screen edge; vertical toolbar layout; `ArrangementView`, `onHingeChange`, and reserved regions available — the Duo-ready level |

Report the project's deployment target and SDK alongside findings — "this is fine today because you build against iOS 26" is real context, and so is "you're on the iOS 27 SDK, so resizability is already live for your users."

## Project & Info.plist audit

- **Orientation keys**: `UISupportedInterfaceOrientations` still matters for discrete resizing and the outer display, but the inner display does not honor it for resizable apps. A portrait-only declaration is not a layout strategy.
- **Launch screen**: a storyboard/`UILaunchScreen` that hardcodes sizes shows as a mis-sized flash on unfold.
- **Scene manifest**: multi-scene support (`UIApplicationSupportsMultipleScenes`) affects iPad and Duo multitasking behavior — check it matches the app's intent rather than being an accidental default.
- **Asset catalogs**: image sets keyed to specific device sizes rather than scale/appearance are a smell on a device with two displays.

## Test coverage

- **Device Hub** (Xcode 27) replaced the separate Simulator and Devices & Simulators windows. It rotates, screenshots, toggles dark mode, changes font size, **resizes freely by dragging edges**, and launches onto connected hardware. **Xcode Previews gained the same resize mode**, plus a Display group for previewing on an alternative display — size-class branches can be exercised without booting a simulator.
- **iPhone Duo simulator (Xcode 27.1).** Install the iOS 27.1 runtime via Settings ▸ Components, then select iPhone Duo as a normal build destination. Toolbar buttons fold/unfold; **hold ⌥ Option for a precise hinge-angle slider**. A review should name which poses were exercised: folded, unfolded, partially open, each orientation, split view, free resize.
- **The recipe that finds real bugs**: navigate several screens deep, open a sheet, start typing — *then* fold and unfold while it's live, in both directions. Most continuity findings only appear this way.
- **What the simulator cannot cover** — flag these as device-only rather than letting a simulator pass stand in: camera transitions between outer / inner / rear cameras, one-handed reachability in partially folded poses, haptics, thermal behavior, and the physical appearance of the fold.
- **Xcode 27.1's "App Resizability" coding-agent skill** (renamed from "App Modernization") auto-detects and fixes common resizability issues in SwiftUI and UIKit. Recommend it as a first pass on a large legacy codebase — then review its edits; it is an agent, not an oracle.
- App Store Connect accepts TestFlight builds made with the iOS 27.1 SDK, so a Duo-ready build can go to testers without waiting for a later toolchain.
- Where the project has UI tests, suggest launching at more than one window size rather than asserting against a single fixed geometry.

## Audit sequence

1. Scene manifest + legacy-window code → launch-blocking findings.
2. `UIRequiresFullScreen` and orientation keys → what fixed-size assumption do they protect?
3. Deployment target / SDK → how live are these findings for users today?
4. Launch screen + asset catalogs → mis-sized first frame.
5. Name the untested poses and window sizes.
