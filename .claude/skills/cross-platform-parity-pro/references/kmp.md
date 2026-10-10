# Kotlin Multiplatform for shared logic

Kotlin Multiplatform (KMP) compiles common Kotlin code for Android and for Apple targets (as a framework Swift can import). Used here for **logic only** — UI stays SwiftUI and Compose so every platform UI rule in this bundle still applies.

KMP tooling moves fast (Swift export, Room KMP, IDE support). Check the current Kotlin and library release notes before committing to a specific integration path.

## When it pays off

Share with KMP when **all** of these hold:

- The logic is large, identical on both platforms, and costly to keep in sync: sync/conflict resolution, offline queues, pricing or eligibility rules, parsers, complex validation.
- The team can own Kotlin and Gradle builds that feed Xcode, and Apple developers are willing to debug through a Kotlin framework.
- The Apple app can accept a Kotlin-produced framework in its build (build time, binary size, crash symbolication for Kotlin frames).

Stay **native × 2** when the shared part is mostly API calls plus mapping (the generated OpenAPI clients already remove most of that), or when the Apple team would treat the shared module as a black box.

Record the decision in an ADR either way.

## What to share and what not to

| Share (commonMain) | Keep native |
|---|---|
| Domain models and business rules | All UI: SwiftUI views, Compose screens, navigation |
| Repositories and their interfaces | Screen state holders (`@Observable` view models / Android ViewModels) |
| Networking (Ktor) and serialization (kotlinx.serialization) | Platform services: notifications, background tasks, widgets, App Intents, Live Activities, WorkManager |
| Local persistence (SQLDelight, or Room's KMP support) | Keychain / Keystore access (expose an interface; implement per platform) |
| Validation, formatting rules that aren't locale UI | Localization resources and accessibility |
| Feature-flag evaluation, analytics event models | Design system and icons |

Platform-specific pieces the shared code needs go through `expect`/`actual` declarations or, better, interfaces implemented on each platform and passed in at startup.

## Module shape

```
shared/
├── build.gradle.kts           # kotlin("multiplatform"): androidTarget(), iosArm64(), iosSimulatorArm64(), macosArm64()…
└── src/
    ├── commonMain/kotlin/     # domain, data, networking
    ├── commonTest/kotlin/     # tests run on every target
    ├── androidMain/kotlin/    # actuals for Android
    └── iosMain/kotlin/        # actuals for Apple targets
```

- DI: Hilt is Android-only. Either construct shared objects with plain constructors and hand them to Hilt modules (Android) and the `AppCore` composition root (Apple), or use a multiplatform DI library inside `shared/` only.
- Delivery to Xcode: a direct Gradle integration into the Xcode build, an XCFramework built by Gradle, or an SPM package wrapping the XCFramework. Pick one; document the command in `apple/CLAUDE.md`.

## A Swift API Apple developers want to use

Kotlin exposes its API to Swift through an Objective-C bridge by default, which makes `Flow`, sealed classes, default arguments, and generics awkward from Swift. Options:

- An interop tool such as SKIE (Touchlab) or KMP-NativeCoroutines to surface `Flow` as `AsyncSequence`, `suspend` as `async`, and sealed hierarchies as Swift enums.
- Kotlin's direct Swift export, as it matures (check its status for your Kotlin version before relying on it).
- **Either way, put a thin Swift adapter at the boundary**: a Swift `actor` conforming to the Swift repository protocol from `apple-repository-pattern.md`, mapping Kotlin types to `Sendable` Swift value types. Feature code depends on the Swift protocol, never on Kotlin types. This keeps Swift 6 strict concurrency intact (Kotlin objects aren't `Sendable`) and lets the Apple side swap the implementation later.

```swift
actor SharedTasksRepository: TasksRepository {
    private let shared: SharedKit.TasksRepository     // Kotlin class from the framework

    init(shared: SharedKit.TasksRepository) { self.shared = shared }

    nonisolated func tasks() -> AsyncStream<[Task]> {
        // Bridge the Kotlin Flow (via the interop layer) and map each emission to Swift values.
        …
    }
}
```

## Testing

- `commonTest` holds the business-rule tests once; they run on JVM and on Apple targets in CI.
- Each platform still tests its adapter and its view models against fakes of the platform-level repository protocol/interface, not against the Kotlin implementation.

## Adoption steps

1. Start with one self-contained slice (a validation module, or one repository) behind the existing Swift protocol and Kotlin interface.
2. Ship it on both platforms; measure build time, binary size, and how the Apple team experiences debugging it.
3. Expand slice by slice; never move UI into `shared/`.
4. If it doesn't pay off, the adapter boundary means the Apple side can go back to a native implementation without touching features.

## Pitfalls

- Sharing view models or UI state across platforms "because we can" — it fights both platforms' UI rules.
- Kotlin types leaking into SwiftUI views — no `Sendable`, awkward APIs, and every feature now depends on the framework.
- No adapter layer — a later change in the interop tool ripples through the whole Apple codebase.
- Hilt or Android-only libraries in `commonMain`.
- Unpinned Kotlin/KMP plugin versions — the Apple build breaks on a Gradle-side bump.
