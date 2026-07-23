// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Starter Package.swift from AppBootstrapAI. Distilled from the production
// Package.swift files in KozBon (KozBonPackages) and BasicSwiftUtilities.
//
// The `makeTargets()` helper at the bottom collapses the per-module boilerplate
// of `.target(...)` + `.testTarget(...)` into a single call. Adding a new module
// is a *two-line* change: one line in `products:` (to expose it) and one
// `+ makeTargets(name: ..., ...)` line in `targets:`.
//
// Prefer to generate this rather than hand-copy it? Run the bundle's
// `scripts/scaffold-spm-package.sh <repo> --modules Core,...,AppCore` — it emits
// this manifest plus compiling module skeletons. See apple-modular-architecture.md
// for the thin-app-shell + local-package architecture this assumes.
//
// Conventions assumed:
//   - One directory per module at the package root.
//   - Inside each module: `Sources/` for source, `Tests/` for tests, optional
//     `Sources/Resources/` for asset/string-catalog/data files.
//   - Test target name is always `<ModuleName>Tests` and depends on the
//     module by `.byName(name: ...)` — no manual cross-referencing.
//   - All targets share the same Swift settings (defined in `sharedSwiftSettings`)
//     so you can't accidentally leave one module on Swift 5 / Swift 6 minor mode.
//
// Replace every `<PLACEHOLDER>` below, then delete this comment block.

import PackageDescription

// MARK: - Shared Settings

/// Swift settings applied to *every* target — both source and test. Keep this
/// short and uniform; per-target overrides are a sign your modules are
/// diverging in ways that will hurt you later.
///
/// The default below assumes Swift 6 strict concurrency. If you're not ready
/// for `.v6` yet, see the commented `swift5Settings` variant below — pick
/// one or the other, don't mix.
let sharedSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("InternalImportsByDefault")
    // Other upcoming features worth considering — read each proposal before enabling:
    // .enableUpcomingFeature("MemberImportVisibility"),  // tighter member import semantics
    // .enableUpcomingFeature("ExistentialAny"),          // require `any P` for protocol existentials
]

// MARK: Alternative Settings — uncomment one if it fits your situation

/// SWIFT 5 with progressive strict-concurrency adoption.
/// Use this while migrating an existing package toward `.v6`. Document a
/// removal date so this doesn't become permanent.
//let sharedSwiftSettings: [SwiftSetting] = [
//    .swiftLanguageMode(.v5),
//    .enableExperimentalFeature("StrictConcurrency"),
//]

/// SWIFT 5 with the equivalent compiler flag (for older toolchains that
/// lack `StrictConcurrency` as a feature flag). Same semantics as the
/// version above; pick whichever your toolchain supports.
//let sharedSwiftSettings: [SwiftSetting] = [
//    .swiftLanguageMode(.v5),
//    .unsafeFlags(["-strict-concurrency=complete"]),
//]

/// SWIFT 6 with per-configuration warning-as-error.
/// Treats warnings as errors only in debug builds, so CI catches them
/// without making release archives needlessly fragile.
//let sharedSwiftSettings: [SwiftSetting] = [
//    .swiftLanguageMode(.v6),
//    .enableUpcomingFeature("InternalImportsByDefault"),
//    .unsafeFlags(["-warnings-as-errors"], .when(configuration: .debug)),
//]

/// SWIFT 6 with a platform-conditional `#if` define for network-capable platforms.
/// Cleaner than `#if os(iOS) || os(macOS) || os(visionOS)` chains in source files.
//let sharedSwiftSettings: [SwiftSetting] = [
//    .swiftLanguageMode(.v6),
//    .enableUpcomingFeature("InternalImportsByDefault"),
//    .define("NETWORK_AVAILABLE", .when(platforms: [.iOS, .macOS, .visionOS])),
//]

// MARK: - Target Helper

/// Creates a source target and (optionally) a test target for a module.
///
/// Directory layout this assumes:
/// ```
/// {name}/
///     Sources/
///         Resources/   (only if hasResources is true)
///     Tests/           (only if hasTests is true)
/// ```
///
/// - Parameters:
///   - name: Module name. Used as both the target name and the on-disk folder.
///   - dependencies: Other targets / package products this module imports.
///     Use `"OtherModule"` for sibling targets in this package,
///     `.product(name: "X", package: "Y")` for external package products.
///   - hasTests: Whether to create a paired test target. Defaults to `true` —
///     missing tests is a problem to fix, not a configuration to support.
///     Set to `false` only for purely declarative resource-only targets.
///   - hasResources: When `true`, the source target picks up
///     `{name}/Sources/Resources/` via `.process("Resources")`. Use for
///     `.xcassets`, `.xcstrings`, `.json` data files, etc.
///   - testDependencies: Additional dependencies the test target needs
///     beyond the module itself (test fixtures from sibling modules, e.g.).
///     The module-under-test is always included automatically.
///   - testResources: Resources for the test target (test fixtures, sample
///     payloads). Less common than source resources.
///   - plugins: Build-tool plugins attached to the source target (e.g.,
///     `SwiftLintBuildToolPlugin`). Test targets don't inherit these by
///     default — pass them explicitly here only if you want lint on source.
func makeTargets(
    name: String,
    dependencies: [Target.Dependency] = [],
    hasTests: Bool = true,
    hasResources: Bool = false,
    testDependencies: [Target.Dependency] = [],
    testResources: [Resource]? = nil,
    plugins: [Target.PluginUsage]? = nil
) -> [Target] {
    var targets: [Target] = [
        .target(
            name: name,
            dependencies: dependencies,
            path: "\(name)/Sources",
            resources: hasResources ? [.process("Resources")] : nil,
            swiftSettings: sharedSwiftSettings,
            plugins: plugins
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

// MARK: - Package

let package = Package(
    name: "<PACKAGE_NAME>",
    platforms: [
        // Pick minimums you actually support. Lowering creates more `#available`
        // guards in code; raising shrinks your audience.
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        // One product per logically separable feature. Consumers `import` these.
        // Internal-only modules can stay out of `products:`.
        .library(name: "Core", targets: ["Core"])
        // .library(name: "CoreUI", targets: ["CoreUI"]),
        // .library(name: "CoreStorage", targets: ["CoreStorage"]),
    ],
    dependencies: [
        // External packages. Prefer `from:` for SemVer-honoring libraries,
        // `exact:` for build reproducibility, `branch:` only during development.
        // .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),

        // Build-tool plugins are package dependencies too. Common ones:
        // .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.63.2"),
        // .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.0"),

        // Local-path dependency for iterating on a sibling package without
        // round-tripping through Git. Mutually exclusive with a URL form for
        // the same package — comment one out, uncomment the other.
        // Don't ship a release with a path: dependency — consumers can't fetch it.
        // .package(path: "../my-sibling-package"),
    ],
    targets:
        // Add one `+ makeTargets(name: "<ModuleName>", ...)` block per module.
        // The `+` operator concatenates the [Target] arrays each call returns.
        makeTargets(
            name: "Core"
        )
        // + makeTargets(
        //     name: "CoreUI",
        //     dependencies: ["Core"],
        //     hasResources: true            // for theme assets, string catalogs, etc.
        // )
        // + makeTargets(
        //     name: "CoreStorage",
        //     dependencies: ["Core"],
        //     testResources: [.process("Resources")]   // for test fixtures
        // )

        // Example: a module with SwiftLint applied as a build-tool plugin.
        // Requires SwiftLintPlugins listed in `dependencies:` above.
        // + makeTargets(
        //     name: "Linted",
        //     plugins: [
        //         .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
        //     ]
        // )
)
