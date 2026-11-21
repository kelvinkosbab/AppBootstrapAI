# API Stability for Swift Libraries

A library has two compatibility contracts:

- **Source compatibility**: consumers' code still compiles against the new version. Every library owes this within a major version.
- **Binary compatibility (ABI)**: an app built against the old binary still runs with the new one. Only libraries built with library evolution (binary XCFrameworks, see `binary-distribution.md`) owe this. Source packages are recompiled with the app, so they only owe source compatibility.

## Design the surface small

- **`internal` by default.** A symbol becomes `public` when a consumer needs it, and stays public until the next MAJOR.
- **`package` access** (Swift 5.9+) for helpers that several modules of the same package share. Before `package`, these became `public` by accident and got frozen into the API.
- **One public entry point per concept.** Prefer a small set of types with clear initializers over many free functions.
- **Initializers are API too.** A `public struct` with an `internal` memberwise init can add stored properties freely; a public memberwise init can't.
- **Configuration through values, not globals.** `public static var shared` and mutable statics make the library untestable for consumers and are data races under Swift 6.
- **Protocols for customization points only.** Every public protocol requirement is permanent; add new ones with a default implementation in an extension.
- **Closed vs open classes.** `public final class` unless subclassing is a designed feature. Removing `open` or `final`-ing a class is breaking.
- **Opaque and existential returns.** `some Collection<Element>` hides the concrete type so it can change; returning `[Element]` or a concrete wrapper freezes it.
- **Imports.** With `InternalImportsByDefault`, a dependency's types can only appear in public signatures through a `public import`, which makes the dependency part of your API (a major bump of theirs can become one of yours). Keep dependency types out of public signatures where you can. `MemberImportVisibility` stops consumers seeing extension members from modules they didn't import.

## Naming

Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/): clarity at the point of use, argument labels that read as phrases, mutating / nonmutating pairs (`sort` / `sorted`), terms of art used consistently. Renaming after release costs a deprecation cycle, so review names before the first tag. The companion [`Swift-API-Design-Guidelines-Agent-Skill`](https://github.com/Erikote04/Swift-API-Design-Guidelines-Agent-Skill) (MIT) does a full naming review.

## Classify every change

| Change | Source | Binary (evolution on) | Bump |
|---|---|---|---|
| Add a public type, function, property | ok | ok | MINOR |
| Add a defaulted parameter to a function | ok (call sites) but breaks function references | **breaks** | MAJOR for binaries; MINOR for source only if no one takes references (prefer a new overload) |
| Add an overload | usually ok; can create ambiguity with literals or `nil` | ok | MINOR, check call sites in tests |
| Remove or rename public symbol | breaks | breaks | MAJOR (deprecate first) |
| Change parameter or return type | breaks | breaks | MAJOR |
| Add `throws`, or change the thrown type | breaks | breaks | MAJOR |
| Remove `throws` / `async` | breaks overrides and conformances | breaks | MAJOR |
| Add protocol requirement without default | breaks conformers | breaks | MAJOR |
| Add protocol requirement with default | ok | ok | MINOR |
| Add enum case | breaks exhaustive switches in source packages | ok if consumers use `@unknown default` (non-frozen) | MAJOR for source packages unless documented non-exhaustive |
| Add stored property to public struct | ok if no public memberwise init | ok unless `@frozen` | MINOR |
| Add `@MainActor` / other isolation to a public type or member | breaks nonisolated callers | breaks | MAJOR |
| Remove `Sendable` conformance | breaks | breaks | MAJOR |
| Add `Sendable` | ok | ok | MINOR |
| Raise a minimum OS in `platforms:` | breaks consumers on that OS | breaks | MAJOR |
| Raise `swift-tools-version` | breaks consumers on older toolchains | n/a | MINOR at most once per year, MAJOR if it drops a supported Xcode |
| Add a dependency | can break version solving | n/a | MINOR, note it in CHANGELOG |
| Behavior change with same signature | compiles, may break at runtime | same | Judge: MAJOR if documented behavior changes |

## Enums that will grow

Public enums in a source package are effectively frozen: adding a case breaks every exhaustive `switch`. Options:

- **A struct with static members** (`public struct LogLevel: Hashable, Sendable { public static let debug = LogLevel(rawValue: 0) }`) when the set is open-ended.
- **Document the enum as non-exhaustive** and ask consumers to add `default:`; then treat a new case as MINOR. Newer toolchains add language support for non-exhaustive enums in source packages (SE-0487); adopt it once your minimum toolchain has it.
- **Error enums**: prefer a struct with a `code` property, or document that new cases may appear.

## Experimental and internal-only API

- **`@_spi(Experimental) public`** for API that is public to opted-in consumers only (`@_spi(Experimental) import MyLib`). SPI is excluded from the stability promise; say so in the README.
- **Separate product** (`MyLibExperimental`) when the experimental surface is large.
- **`@_documentation(visibility: internal)`** hides a symbol from DocC without changing its access. It is not a stability escape hatch.

## Deprecation lifecycle

1. Add the replacement (MINOR).
2. Deprecate the old symbol in the same or a later MINOR:

   ```swift
   @available(*, deprecated, renamed: "fetch(id:)")
   public func load(identifier: String) async throws -> Item { try await fetch(id: identifier) }

   @available(*, deprecated, message: "Use Client(configuration:). Removed in 3.0.")
   public init(apiKey: String) { … }
   ```

3. Remove in the next MAJOR and list it under **Removed** in CHANGELOG.

Never deprecate without `renamed:` or a `message:` naming the replacement. `obsoleted:` is for platform-versioned APIs, not library versions.

## The breaking-change gate

SwiftPM compares the current API against a git ref using the API digester:

```bash
swift package diagnose-api-breaking-changes 1.4.0
# limit to products / targets:
swift package diagnose-api-breaking-changes 1.4.0 --products MyLib
# record accepted breaks in a file (one per line) for a major release:
swift package diagnose-api-breaking-changes 1.4.0 --breakage-allowlist-path api-breakage-allowlist.txt
```

- Run it on a macOS runner (it needs the Xcode toolchain's digester), with full git history (`fetch-depth: 0`) so the tag exists.
- Compare against the latest release tag, not `main`, so breaks accumulated across PRs are visible.
- It catches signature and declaration changes. It does not catch behavior changes, `Package.swift` changes (platforms, tools version, dependencies), or isolation changes it can't see; review those by hand.
- For binary frameworks, also diff the `.swiftinterface` files between releases (`binary-distribution.md`).

## Concurrency is API

- A public type's isolation (`@MainActor`, an actor, nonisolated) and its `Sendable` conformance are part of the contract. Decide them before 1.0.
- Public closures parameters: mark `@Sendable` (or `sending`) when they cross isolation; removing `@Sendable` later is fine, adding it is breaking.
- Prefer `async` APIs over completion handlers in new libraries; when both exist, the completion-handler form is the one to deprecate.
- Don't expose a `@MainActor` default isolation from a library module (`.defaultIsolation(MainActor.self)` is for app UI modules).
