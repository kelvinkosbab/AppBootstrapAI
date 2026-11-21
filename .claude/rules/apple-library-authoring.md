---
description: Authoring Swift libraries and Apple frameworks that apps consume — minimal public surface, package access, SemVer with an automated breaking-change check, library evolution only for binary frameworks, signed XCFrameworks with privacy manifests, and CI on every platform you claim
globs: "**/*.swift,**/Package.swift,**/.spi.yml"
paths:
  - "**/*.swift"
  - "**/Package.swift"
  - "**/.spi.yml"
must:
  - "Default to `internal` or `package`; every `public` symbol is a SemVer promise."
  - "Run `swift package diagnose-api-breaking-changes <last-tag>` in CI and bump MAJOR for any break it reports."
  - "Library evolution (`BUILD_LIBRARY_FOR_DISTRIBUTION`) only for binary frameworks, never for a source package."
  - "Ship XCFrameworks signed, with a PrivacyInfo.xcprivacy, and as a checksummed `.binaryTarget`."
  - "Build and test every platform listed in `platforms:` in CI, not just macOS."
---

# Apple Library Authoring

For repos whose product is a Swift package or Apple framework that other apps depend on. App code can be refactored freely; a library's public API, minimum OS, and binary layout are promises to people you can't see. The `swift-library-pro` skill covers each section in depth; `swift-package-pro` owns `Package.swift` itself (`apple-spm-package-conventions.md`).

## Public surface

- **`internal` by default; `package` for helpers shared between modules of the same package** (Swift 5.9+). `public` only for what a consumer calls. `open` only for classes designed to be subclassed, with the overridable points documented.
- **`InternalImportsByDefault` and `MemberImportVisibility` on**, so a dependency never leaks into consumers' namespaces unless a `public import` says so.
- **No public global mutable state, no singletons consumers can't replace.** Take configuration through initializers.
- **Public types are `Sendable` when they can be** and declare their isolation. Removing `Sendable` or adding `@MainActor` later is a breaking change.
- **No public retroactive conformances** (`extension Foreign: ForeignProtocol`, which needs `@retroactive`). Two libraries doing it collide in the app.
- **Experimental API behind `@_spi(Name)`** or a separate product, never a `public` symbol with a "do not use" comment.
- **Name APIs by the Swift API Design Guidelines** (argument labels, clarity at the point of use). The design is reviewed before the first tag, not after.

## Versioning and breaking changes

- **SemVer with tags `1.2.3`.** Breaking: removing or renaming public symbols, changing a signature (including adding a parameter, even defaulted, for binary frameworks), changing `throws` or the thrown type, adding a protocol requirement without a default, adding an enum case to a public enum consumers switch over, removing a conformance, tightening isolation, raising a minimum OS.
- **Automate the check**: `swift package diagnose-api-breaking-changes <last-tag>` on a macOS runner for every PR. A reported break means a MAJOR bump or a redesign, never an ignored warning.
- **Deprecate before removing**: `@available(*, deprecated, renamed:)` for at least one MINOR release, removal in the next MAJOR, all in `CHANGELOG.md`.
- **Public enums that will grow** get a struct-with-static-members design or are documented as non-exhaustive; consumers of a binary framework must handle `@unknown default`.
- **`Package.resolved` is git-ignored**, dependency ranges are `from:` the oldest version you test against, and every dependency is one more version-solve constraint on the app.

## Binary distribution

- **Source package first.** Ship an XCFramework only when the source can't be shared.
- **Library evolution only for binaries**: `BUILD_LIBRARY_FOR_DISTRIBUTION = YES` in the archive that produces the XCFramework. It changes codegen (resilience) and is not a setting for a source package.
- **`@frozen` and `@inlinable` are permanent ABI promises** in a resilient library. Add them only for measured hot paths; never remove them.
- **One XCFramework with every slice you support** (device and simulator per platform, Mac Catalyst if claimed), dSYMs included with `-debug-symbols`.
- **Sign the XCFramework** (`codesign --timestamp`) with a stable identity and **include `PrivacyInfo.xcprivacy`** in each framework declaring required-reason APIs and collected data. Apps can't pass review with your SDK otherwise.
- **`.binaryTarget(url:checksum:)`** with the checksum from `swift package compute-checksum`. Never a `path:` binary in a released manifest.
- **No public type named the same as its module**: it breaks the generated `.swiftinterface`.

## Quality bar

- **CI builds and tests every platform in `platforms:`**: `swift test` on macOS and Linux if you claim Linux, `xcodebuild build` (and `test` where possible) with `generic/platform=iOS`, `tvOS`, `watchOS`, `visionOS`, against the oldest and newest Xcode you support.
- **Every public symbol documented**, a DocC catalog with a getting-started article, and `.spi.yml` declaring `documentation_targets` if listed on the Swift Package Index.
- **Tests exercise the public API** from a test target that imports the module without `@testable` for at least one suite, so a missing `public` fails CI.
- **An Examples/ app or snippet that compiles in CI** proves the README's code.
- **Minimum OS is a product decision**: raising it is MAJOR. Don't adopt a new API by raising the floor when `if #available` works.
