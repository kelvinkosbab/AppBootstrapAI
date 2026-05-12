---
description: Conventions for authoring Swift Package Manager Package.swift files — tool-version pinning, platforms, products, per-module folder layout, resources, modern features, dependency hygiene
globs: "Package.swift,**/Package.swift"
---

# Swift Package Manager: Package.swift Conventions

Authoring strategy for `Package.swift`. Complements the `swift-package-pro` skill (which reviews public API, module organization, and dependency hygiene) by covering the manifest itself — what to pin, where to declare platforms, how to lay out modules, and which modern SPM features to opt into.

> **Starter template:** [`templates/Package.template.swift`](../../templates/Package.template.swift) is a ready-to-edit `Package.swift` that uses the `makeTargets()` helper pattern below. For a new package, copy that file in instead of writing the manifest from scratch.

## Tool Version Pinning

```swift
// swift-tools-version: 6.0
import PackageDescription
```

- **Pin to the lowest tools version that has the features you use** — every developer building the package must have at least this Swift toolchain. Setting it too high blocks contributors on older Xcodes; setting it too low denies you newer manifest features.
- **Don't bump the tools version unless you actually adopt a feature gated behind it.** Cosmetic bumps for "latest" surprise contributors mid-PR.
- The first line is *not* a comment in the conventional sense — SPM parses it. It must be the first line, with exact spacing.

## Platforms

```swift
let package = Package(
    name: "MyPackage",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    // ...
)
```

- **Always declare `platforms:`** for any package targeting Apple platforms — without it, SPM falls back to old defaults that won't have the APIs you use.
- **Pick minimums you actually support** — declaring `iOS(.v15)` when your code uses `iOS 17` APIs creates confusing build errors at consumer sites instead of clean ones at your site.
- **Drop a platform from the list only if every type and import would need to be platform-guarded.** Half-supported platforms (`#if !os(watchOS)` everywhere) make consumers' builds brittle.

## Products

```swift
products: [
    .library(name: "Core", targets: ["Core"]),
    .library(name: "CoreUI", targets: ["CoreUI"]),
    .executable(name: "my-cli", targets: ["MyCLI"]),
],
```

- **One product per logically separable feature** — bundling all internal modules into a single mega-product forces consumers to import everything.
- **Default to `.library(name:targets:)`** without specifying `type:` (the default is dynamic on Apple platforms with linker-driven dead-code stripping; consumers can request `.static` if they need it).
- **Don't expose internal-only modules as products.** Products are the package's public API surface; internal modules support targets but stay implicit.

## Per-Module Folder Layout

For a multi-module package, use the per-module directory convention with **flat `Sources/`** and `Tests/` inside each module folder (not nested under another `<ModuleName>/` directory):

```
MyPackage/
├── Package.swift
├── Core/
│   ├── Sources/
│   │   └── *.swift
│   └── Tests/
│       └── *.swift
├── CoreUI/
│   ├── Sources/
│   │   ├── Resources/       (if the module ships assets/strings)
│   │   └── *.swift
│   └── Tests/
│       └── *.swift
└── README.md
```

- **`{Module}/Sources/`** holds the source, **`{Module}/Tests/`** holds the tests. `path:` strings in target declarations match this layout 1:1 (`path: "\(name)/Sources"`, `path: "\(name)/Tests"`).
- **Don't pile every module's sources into a flat top-level `Sources/`** unless you have exactly one module. Discoverability degrades fast at 4+ modules.
- **`{Module}/` directory at the package root** keeps each module self-contained and shows up cleanly in Xcode's navigator.
- **Resources sit at `{Module}/Sources/Resources/`** when present — uniform across modules, so the manifest just toggles `hasResources: true` (see the helper above) without needing bespoke `[Resource]` arrays per module.

## `makeTargets()` Helper for Many Similar Modules

When 2+ modules share the same shape (paired source + test target, optional resources, uniform Swift settings), reduce duplication with a helper at the bottom of `Package.swift`. The canonical version lives in [`templates/Package.template.swift`](../../templates/Package.template.swift) — copy that file rather than rewriting the helper each project. Signature:

```swift
func makeTargets(
    name: String,
    dependencies: [Target.Dependency] = [],
    hasTests: Bool = true,
    hasResources: Bool = false,
    testDependencies: [Target.Dependency] = [],
    testResources: [Resource]? = nil
) -> [Target]
```

**Usage** — adding a new module is a two-line change (one `product:` line, one `+ makeTargets(...)` block):

```swift
targets:
    makeTargets(name: "Core")
    + makeTargets(name: "CoreUI", dependencies: ["Core"], hasResources: true)
    + makeTargets(name: "CoreStorage", dependencies: ["Core"], testResources: [.process("Resources")])
```

- **The helper is local to `Package.swift`** — *don't* try to share it across packages via SPM (you can't import code into the manifest). Each package gets its own copy of `makeTargets()` and `sharedSwiftSettings`.
- **`hasResources` follows a folder convention** — `{Module}/Sources/Resources/`. Keeping the on-disk layout uniform across modules means the manifest doesn't need bespoke `[Resource]` arrays per module.
- **`hasTests: false` is for declarative resource-only targets** (a target that just ships strings or data files). Default is `true` — a missing test target is a problem to fix, not a config to support.
- **`testDependencies` adds modules the tests need beyond the module-under-test** — typically test fixtures from sibling modules. The module itself is always injected via `.byName(name:)`.

## Resources

```swift
.target(
    name: "BonjourLocalization",
    dependencies: [],
    path: "BonjourLocalization/Sources/BonjourLocalization",
    resources: [
        .process("Localizable.xcstrings"),
        .process("Resources")
    ]
)
```

- **`.process(...)`** is the default — SPM compiles `.xcassets`, `.xcstrings`, `.storyboard`, etc. and namespaces resources for `Bundle.module` access.
- **`.copy(...)`** is for files SPM should *not* compile or rename (raw data files, fixtures with deliberate paths). Rare.
- **Always access resources via `Bundle.module`** in code (`Bundle.module.url(forResource:withExtension:)`) — never `Bundle.main` (which is the consumer's app bundle, not yours).
- **Core Data caveat:** SPM cannot compile `.xcdatamodeld` files via the CLI. Either ship the model as raw resources and build the `NSManagedObjectModel` programmatically (see `coredata-swift6-pro` skill), or require Xcode for the build path that needs it.

## Modern Features (Swift 6+)

```swift
.target(
    name: "Core",
    dependencies: [],
    path: "Core/Sources/Core",
    swiftSettings: [
        .swiftLanguageMode(.v6),
        .enableExperimentalFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility")
    ]
)
```

- **`.swiftLanguageMode(.v6)`** opts into Swift 6 strict concurrency at the target level. Combine with the `apple-swift6-strict-concurrency.md` rule for full coverage.
- **`InternalImportsByDefault`** — module imports are `internal` unless marked `public import`. Forces explicit re-exports; catches accidental public-API leaks where an `import` of a dependency module makes it part of your package's public surface.
- **`public import` for re-exported types only** — when a public function's signature uses a type from a dependency module (`func make() -> SomeKit.SomeType`), the import must be `public`. Plain `import` is internal.

## Dependencies

```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),
    .package(url: "https://github.com/apple/swift-async-algorithms", exact: "1.0.0")
],
```

- **`from:` (open-ended major version)** for libraries you trust to honor SemVer (Apple's own packages, well-maintained community libs).
- **`exact:`** for executables that must reproduce the same build, or for dependencies whose maintainers don't honor SemVer.
- **`branch:` / `revision:`** for development pins only — never ship a release with a branch dependency. Consumers can't predict when a branch moves under them.
- **Avoid transitive dependency duplication.** If `Core` depends on `swift-collections` and `CoreUI` does too, the version unifies via the package's top-level dependencies — declare it once at the top, then reference `.product(name: "Collections", package: "swift-collections")` from each target.

## Test Targets

```swift
.testTarget(
    name: "CoreTests",
    dependencies: ["Core"],
    path: "Core/Tests/CoreTests"
)
```

- **`@testable import Core`** in tests gives access to `internal` symbols. Use it for testing internals; use plain `import Core` to test the public API.
- **Test targets don't need to declare platforms separately** — they inherit the package's `platforms:`.
- **Don't use `.testTarget(...)` for UI tests** — UI tests need an app host and live in an `.xctestplan` outside SPM. Keep UI tests in the consumer Xcode project.

## Common Pitfalls

- **Missing `platforms:`** — falls back to ancient defaults; APIs you use aren't available; build fails at consumer sites with cryptic errors.
- **Path mismatches** — `path:` strings that don't reflect on-disk reality silently exclude sources. SPM doesn't validate paths until build time.
- **`.copy(...)` when `.process(...)` was meant** — `.copy` ships the file verbatim with no compilation. `.xcassets` copied won't work.
- **Bundle.main vs Bundle.module** — using `Bundle.main` to load a packaged resource works in single-target tests but breaks the moment a consumer app uses the package.
- **`unsafeFlags(...)`** — disqualifies the package from being a dependency of other published packages. Reserve for executables and CLIs, never libraries.
- **Branch dependencies in `from:` ranges** — accidentally pinning to a branch via `from: "0.0.0-pre.1"` etc. Set explicit `branch:` if you mean it, otherwise prefer tagged releases.
- **`@_implementationOnly import` after enabling `InternalImportsByDefault`** — the new feature replaces the old underscore-prefix attribute; don't mix.
- **Duplicate platform spelling** — `.iOS(.v17)` and `.macOS("13.0")` mixing literal and shorthand forms. Pick one form per package.

## Patterns to Follow

The canonical version of this pattern lives in [`templates/Package.template.swift`](../../templates/Package.template.swift). Abridged here for reference:

```swift
// swift-tools-version: 6.0
import PackageDescription

let sharedSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("InternalImportsByDefault")
]

func makeTargets(
    name: String,
    dependencies: [Target.Dependency] = [],
    hasTests: Bool = true,
    hasResources: Bool = false,
    testDependencies: [Target.Dependency] = [],
    testResources: [Resource]? = nil
) -> [Target] {
    var targets: [Target] = [
        .target(
            name: name,
            dependencies: dependencies,
            path: "\(name)/Sources",
            resources: hasResources ? [.process("Resources")] : nil,
            swiftSettings: sharedSwiftSettings
        )
    ]
    if hasTests {
        targets.append(
            .testTarget(
                name: "\(name)Tests",
                dependencies: [.byName(name: name)] + testDependencies,
                path: "\(name)/Tests",
                resources: testResources,
                swiftSettings: sharedSwiftSettings
            )
        )
    }
    return targets
}

let package = Package(
    name: "MyPackage",
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "CoreUI", targets: ["CoreUI"]),
        .library(name: "CoreStorage", targets: ["CoreStorage"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.0")
    ],
    targets:
        makeTargets(
            name: "Core",
            dependencies: [.product(name: "Collections", package: "swift-collections")]
        )
        + makeTargets(
            name: "CoreUI",
            dependencies: ["Core"],
            hasResources: true   // pulls CoreUI/Sources/Resources/ automatically
        )
        + makeTargets(
            name: "CoreStorage",
            dependencies: ["Core"],
            testResources: [.process("Resources")]
        )
)
```

Adding `CoreNetworking` is now a **two-line change**: a new `.library(name: "CoreNetworking", targets: ["CoreNetworking"])` in `products:`, and a new `+ makeTargets(name: "CoreNetworking", dependencies: ["Core"])` block in `targets:`. The Swift settings, path conventions, and test-target wiring all come for free.
