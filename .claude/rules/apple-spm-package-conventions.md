---
description: Conventions for authoring Swift Package Manager Package.swift files — tool-version pinning, platforms, products, per-module folder layout, resources, modern features, dependency hygiene
globs: "Package.swift,**/Package.swift"
---

# Swift Package Manager: Package.swift Conventions

Authoring strategy for `Package.swift`. Complements the `swift-package-pro` skill (which reviews public API, module organization, and dependency hygiene) by covering the manifest itself — what to pin, where to declare platforms, how to lay out modules, and which modern SPM features to opt into.

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

For a multi-module package, use the per-module directory convention:

```
MyPackage/
├── Package.swift
├── Core/
│   ├── Sources/
│   │   └── Core/
│   │       └── ...
│   └── Tests/
│       └── CoreTests/
│           └── ...
├── CoreUI/
│   ├── Sources/
│   │   └── CoreUI/
│   └── Tests/
│       └── CoreUITests/
└── README.md
```

- **`{Module}/Sources/{Module}/`** for source, **`{Module}/Tests/{Module}Tests/`** for tests — explicit `path:` in target declarations matches this layout.
- **Don't pile every module's sources into a flat `Sources/`** unless you have exactly one module. Discoverability degrades fast at 4+ modules.
- **`{Module}/` directory at the package root** is symmetric with how Xcode workspaces show local packages — keeps the navigator tidy.

## `makeTargets()` Helper for Many Similar Modules

When 4+ modules share the same shape (regular target + test target, same path convention), reduce boilerplate with a helper at the bottom of `Package.swift`:

```swift
let package = Package(
    name: "MyPackage",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "CoreUI", targets: ["CoreUI"]),
        .library(name: "CoreStorage", targets: ["CoreStorage"]),
    ],
    targets: makeTargets(
        ("Core", []),
        ("CoreUI", ["Core"]),
        ("CoreStorage", ["Core"])
    )
)

func makeTargets(_ specs: (name: String, dependencies: [String])...) -> [Target] {
    specs.flatMap { spec -> [Target] in
        let deps: [Target.Dependency] = spec.dependencies.map { .target(name: $0) }
        return [
            .target(
                name: spec.name,
                dependencies: deps,
                path: "\(spec.name)/Sources/\(spec.name)"
            ),
            .testTarget(
                name: "\(spec.name)Tests",
                dependencies: [.target(name: spec.name)],
                path: "\(spec.name)/Tests/\(spec.name)Tests"
            )
        ]
    }
}
```

- The helper is local to `Package.swift` — *don't* try to share it across packages via SPM (you can't import code into the manifest).
- **Keep it small.** Once the helper has more parameters than the targets it's saving keystrokes on, write the targets out by hand.

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

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyPackage",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "CoreUI", targets: ["CoreUI"]),
        .library(name: "CoreStorage", targets: ["CoreStorage"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.0")
    ],
    targets: makeTargets(
        ("Core",        ["Collections"], []),
        ("CoreUI",      [],              ["Core"]),
        ("CoreStorage", [],              ["Core"])
    )
)

func makeTargets(
    _ specs: (
        name: String,
        productDependencies: [String],
        targetDependencies: [String]
    )...
) -> [Target] {
    specs.flatMap { spec -> [Target] in
        let deps: [Target.Dependency] =
            spec.productDependencies.map { .product(name: $0, package: "swift-collections") } +
            spec.targetDependencies.map  { .target(name: $0) }

        let modernSettings: [SwiftSetting] = [
            .swiftLanguageMode(.v6),
            .enableExperimentalFeature("InternalImportsByDefault")
        ]

        return [
            .target(
                name: spec.name,
                dependencies: deps,
                path: "\(spec.name)/Sources/\(spec.name)",
                swiftSettings: modernSettings
            ),
            .testTarget(
                name: "\(spec.name)Tests",
                dependencies: [.target(name: spec.name)],
                path: "\(spec.name)/Tests/\(spec.name)Tests",
                swiftSettings: modernSettings
            )
        ]
    }
}
```
