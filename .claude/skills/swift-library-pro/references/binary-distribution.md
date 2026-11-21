# Binary Distribution: XCFrameworks and Library Evolution

## Ship source unless you can't

A source package compiles with the app's toolchain and settings, supports every platform SwiftPM does, and needs no ABI promises. Ship a binary only when the source can't be shared (closed SDK), build time is a real problem for consumers, or the library is consumed by apps that can't build its dependencies. A binary costs you: an archive per platform, library evolution's restrictions, signing, and a release pipeline.

## Library evolution and module stability

- **`BUILD_LIBRARY_FOR_DISTRIBUTION = YES`** turns on library evolution (resilient layout) and emits a textual `.swiftinterface`. That makes the binary usable from newer Swift compilers (module stability) and lets you add stored properties, cases, and methods without breaking apps built against an older version (ABI stability).
- **Set it only on the archive that builds the binary**, and on every dependency inside the framework. Never in a source package's `Package.swift`: it needs `.unsafeFlags(["-enable-library-evolution"])`, which makes the package unconsumable, and it slows the code down.
- **Resilience has a cost**: outside the module, layouts of non-frozen types are unknown, so access goes through indirection. That's why the attributes below exist.

### `@frozen`, `@inlinable`, `@usableFromInline`

- **`@frozen` struct / enum**: layout is fixed forever. No stored property may be added, removed, or reordered; no case added. Use only for tiny value types where the indirection is measured (`Point`, `Color` components).
- **`@inlinable` function**: its body is part of the ABI and gets compiled into the app. Old app binaries keep running the old body after you ship a fix. Use for small generic hot paths only, and never for anything with a security or correctness fix likely.
- **`@usableFromInline internal`**: internal symbols an `@inlinable` body calls. They become ABI too.
- In a source package (no evolution), `@inlinable` still enables cross-module specialization; `@frozen` does nothing. Don't sprinkle either "for performance" without a benchmark.
- These three can be added in a MINOR release and **can never be removed**.

## Building an XCFramework

Archive once per platform variant, then combine:

```bash
set -euo pipefail
SCHEME=MyLib
for DEST in "generic/platform=iOS" "generic/platform=iOS Simulator" \
            "generic/platform=macOS" "generic/platform=macOS,variant=Mac Catalyst" \
            "generic/platform=tvOS" "generic/platform=tvOS Simulator" \
            "generic/platform=watchOS" "generic/platform=watchOS Simulator" \
            "generic/platform=visionOS" "generic/platform=visionOS Simulator"; do
  NAME=$(echo "$DEST" | tr ' =,/' '____')
  xcodebuild archive -scheme "$SCHEME" -destination "$DEST" \
    -archivePath "build/$NAME.xcarchive" \
    SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES DEBUG_INFORMATION_FORMAT=dwarf-with-dsym
done

ARGS=()
for A in build/*.xcarchive; do
  ARGS+=(-archive "$A" -framework "$SCHEME.framework")
done
xcodebuild -create-xcframework "${ARGS[@]}" -output "build/$SCHEME.xcframework"
```

- Archive only the platforms in your `platforms:` list; drop the rest from the loop.
- `-create-xcframework -archive … -framework …` picks up the dSYMs from each archive automatically; with `-framework <path>` inputs, pass `-debug-symbols <abs path to dSYM>` per slice.
- **Archive the framework target of an Xcode project**, or a SwiftPM library product with `type: .dynamic` through `xcodebuild` (SwiftPM static products archive as object files, not frameworks). Pick one and script it.
- **Resources**: a framework carries its own bundle; load with `Bundle(for: SomeClass.self)` or a generated accessor, never `Bundle.main` or `Bundle.module` (that's SwiftPM source targets only).
- **Static vs dynamic**: dynamic frameworks are simplest for consumers. A static XCFramework with resources needs a separate resource bundle.

## Signing

- Xcode 15+ shows and verifies the signature of every XCFramework an app links, and warns when an identity changes between versions. Sign every release with the same identity:

  ```bash
  codesign --timestamp -v --sign "Apple Distribution: Example Inc (TEAMID)" build/MyLib.xcframework
  codesign --verify --verbose build/MyLib.xcframework
  ```

- Use a Developer ID or Apple Distribution certificate held in CI secrets (`apple-testflight-deployment.md` covers keychain import). Never ship unsigned or ad-hoc-signed SDKs.

## Privacy manifests

- Each framework in the XCFramework contains its own `PrivacyInfo.xcprivacy` declaring: data the SDK collects (`NSPrivacyCollectedDataTypes`), tracking domains, and required-reason API usage (`NSPrivacyAccessedAPITypes`: UserDefaults, file timestamps, disk space, system boot time, active keyboards).
- Apple's list of commonly used third-party SDKs must ship a manifest and a signature; every SDK should, because the app's privacy report aggregates them.
- For source packages, put `PrivacyInfo.xcprivacy` in the target's resources (`.process("Resources")` or `.copy("PrivacyInfo.xcprivacy")`).

## Distributing through SwiftPM

```swift
.binaryTarget(
    name: "MyLib",
    url: "https://github.com/example/mylib/releases/download/2.1.0/MyLib.xcframework.zip",
    checksum: "<output of swift package compute-checksum>"
)
```

```bash
(cd build && zip -ry MyLib.xcframework.zip MyLib.xcframework)   # -y keeps framework symlinks (macOS)
swift package compute-checksum build/MyLib.xcframework.zip
```

- The zip is uploaded to the release before the tag's `Package.swift` points at it. Usual order: build → zip → checksum → commit manifest with URL and checksum → tag → upload asset under that tag.
- A binary target can't declare dependencies. If the SDK needs another package, wrap it: a thin source target depends on both the `.binaryTarget` and the dependency, and the product exposes the wrapper.
- Binary targets work only on Apple platforms.
- Consider a separate "binary" repo whose `Package.swift` only references released zips, so consumers don't clone your source history.

## Mixed Objective-C frameworks

- A public umbrella header lists every public header; private headers stay out of it.
- `NS_ASSUME_NONNULL_BEGIN` / `END`, lightweight generics, and `NS_SWIFT_NAME` on every public header (`apple-objc-best-practices.md`). Swift consumers see your header annotations as API.
- `NS_REFINED_FOR_SWIFT` plus a Swift overlay for C-style APIs.
- Changing an Objective-C header's nullability or generic type is source-breaking for Swift consumers.

## Checking the interface between releases

- Keep the previous release's `.swiftinterface` files (from the XCFramework's `Modules/MyLib.swiftmodule/`) and diff them in CI. Every removed or changed line is a binary break; review added `@frozen` and `@inlinable` lines with extra care.
- Xcode verifies the emitted interface when building for distribution. A failure there usually means the interface can't be re-parsed.

## Gotchas

- **A public type with the same name as its module** (`MyLib.MyLib`) makes the `.swiftinterface` ambiguous and can fail to import. Rename the type or the module.
- **Missing slices**: an app building for the visionOS simulator fails with "no library for this platform". Ship every slice of every platform you claim.
- **Mixing `-enable-library-evolution` in the framework with a non-evolution dependency** compiled into it breaks at link or load. Build every module inside the binary with evolution.
- **Static XCFrameworks pulled in twice** (two frameworks both embedding the same static library) give duplicate symbols or two copies of global state.
- **Debug symbols**: ship dSYMs (inside the XCFramework or as a separate asset) so consumers' crash reports symbolicate your frames.
