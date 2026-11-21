# CI and Releases for Swift Libraries

## Build every platform you claim

`swift build` and `swift test` on a Mac build for macOS only. A package that says `.iOS(.v17), .watchOS(.v10)` and only runs `swift test` has never compiled for watchOS. The matrix:

| Job | Runner | Command |
|---|---|---|
| macOS tests | macOS | `swift test --parallel` |
| iOS / tvOS / visionOS tests | macOS | `xcodebuild test -scheme MyLib -destination 'platform=iOS Simulator,name=iPhone 17'` (SwiftPM packages get an auto-generated scheme; `-scheme MyLib-Package` builds every target) |
| watchOS build | macOS | `xcodebuild build -scheme MyLib -destination 'generic/platform=watchOS'` (test where the simulator supports it) |
| Mac Catalyst | macOS | `xcodebuild build -scheme MyLib -destination 'generic/platform=macOS,variant=Mac Catalyst'` |
| Linux (if claimed) | Linux | `swift test` in the `swift:6.x` image; guard Apple-only code with `#if canImport(Darwin)` |
| Oldest supported Xcode | macOS | the build jobs again with the oldest Xcode in your README |
| API break gate | macOS | `swift package diagnose-api-breaking-changes <last-tag>` |
| Docs | macOS or Linux | `swift package generate-documentation --warnings-as-errors` (swift-docc-plugin) |
| Lint | any | `swiftlint lint --strict` as a step, never a build plugin consumers inherit |

- **Pin Xcode per job** (`sudo xcode-select -s /Applications/Xcode_26.x.app` or `maxim-lobanov/setup-xcode`) and print `swift --version` so failures are reproducible.
- **Test with warnings as errors in CI only** (`-Xswiftc -warnings-as-errors` on the command line, or `.treatAllWarnings(as: .error)` gated on an environment variable), never as an `unsafeFlags` in the published manifest.
- **Resolve fresh**: libraries don't commit `Package.resolved`, so CI tests against the newest dependency versions in range. Add a weekly scheduled run so a dependency release that breaks you is caught before a consumer finds it, and optionally a job pinned to the lowest allowed versions.
- **Examples compile**: build `Examples/` (or doc snippets) in CI so README code can't rot.

## Swift Package Index

The [Swift Package Index](https://swiftpackageindex.com) builds every package against several Swift versions and platforms and hosts DocC. Add `.spi.yml` at the root:

```yaml
version: 1
builder:
  configs:
    - documentation_targets: [MyLib]
    # - platform: ios
    #   scheme: MyLib     # when the auto-detected scheme isn't the one to build
```

- Its compatibility matrix is a public claim; keep it green by matching your CI matrix to it.
- `documentation_targets` lists only modules with public API.

## Package traits for optional features

Swift 6.1+ (tools 6.1) packages can declare **traits** so consumers opt into optional dependencies instead of every app pulling them in:

```swift
traits: [
    .default(enabledTraits: []),
    .trait(name: "Logging", description: "Integrates swift-log"),
],
dependencies: [
    .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
],
targets: [
    .target(name: "MyLib", dependencies: [
        .product(name: "Logging", package: "swift-log", condition: .when(traits: ["Logging"])),
    ]),
]
```

Code checks `#if Logging`. Test each trait combination you support in CI. Before tools 6.1, ship the optional integration as a separate product (`MyLibLogging`).

## Versioning

- **Tags are bare SemVer**: `1.4.0`. SwiftPM accepts `v1.4.0` but the bare form is the convention, and mixing both confuses `from:` resolution.
- **Pre-releases**: `2.0.0-beta.1`. Consumers only get them by asking explicitly (`exact:` or a range that includes the pre-release).
- **0.x**: MINOR may break. Ship 1.0 once the API has survived real consumers; don't stay on 0.x forever to avoid commitment.
- **Supported toolchains** are part of the contract: write "Swift 6.0+ / Xcode 16+" in the README and test the oldest. Dropping one is at least MINOR and noted in CHANGELOG; MAJOR if many consumers are on it.
- **Long-term branches** (`release/2.x`) only if you commit to backporting fixes; say so in the README.

## Release checklist

1. `main` green on the whole matrix.
2. `swift package diagnose-api-breaking-changes <last-tag>`: reported breaks match the version you're about to tag.
3. Hand-review what the gate can't see: `platforms:`, `swift-tools-version`, new dependencies, behavior changes, isolation changes.
4. CHANGELOG `[Unreleased]` moved under the new version with today's date (Keep a Changelog headings: Added, Changed, Deprecated, Removed, Fixed, Security).
5. Docs build without warnings; README install snippet shows the new version (`from: "2.1.0"`).
6. For binaries: build, sign, zip, checksum, update `Package.swift`, then tag (`binary-distribution.md`).
7. Tag `X.Y.Z` on the release commit and push the tag; CI creates the GitHub Release with the CHANGELOG section as notes and attaches binaries.
8. After a MAJOR: a migration guide (DocC article or `MIGRATING.md`) listing each removed API and its replacement.

## GitHub Actions example

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:
  schedule: [{ cron: "0 6 * * 1" }]   # weekly: catch dependency releases

jobs:
  macos:
    runs-on: macos-15
    strategy:
      matrix:
        xcode: ["16.4", "26.1"]       # oldest supported, newest
        destination:
          - "platform=macOS"
          - "platform=iOS Simulator,name=iPhone 16"
          - "generic/platform=watchOS"
          - "generic/platform=tvOS"
    steps:
      - uses: actions/checkout@v4
      - run: sudo xcode-select -s /Applications/Xcode_${{ matrix.xcode }}.app
      - name: Build and test
        run: |
          ACTION=test
          case "${{ matrix.destination }}" in generic/*) ACTION=build ;; esac
          xcodebuild "$ACTION" -scheme MyLib -destination "${{ matrix.destination }}"

  linux:
    runs-on: ubuntu-latest
    container: swift:6.2
    steps:
      - uses: actions/checkout@v4
      - run: swift test --parallel

  api-breakage:
    if: github.event_name == 'pull_request'
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - name: Diagnose API breaking changes
        run: |
          LAST_TAG=$(git describe --tags --abbrev=0)
          swift package diagnose-api-breaking-changes "$LAST_TAG"

  docs:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: swift package generate-documentation --target MyLib --warnings-as-errors
```

Adjust simulator names and Xcode versions to what the runner image provides; the docs job needs the `swift-docc-plugin` dependency in `Package.swift`.

An intended MAJOR release makes the `api-breakage` job fail by design. Either label the PR and skip the job, or pass `--breakage-allowlist-path` with the accepted breaks listed, and delete the allowlist after tagging.
