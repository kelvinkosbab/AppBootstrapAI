---
name: android-library-pro
description: Builds, reviews, and publishes Android and Kotlin library modules that apps depend on — library module setup (namespace, resource prefix, AAR metadata, Kotlin and SDK floors), explicit API mode, binary compatibility and ABI dumps (binary-compatibility-validator, KGP abiValidation), Java interop, consumer R8 rules, Compose library APIs, Dokka, and signed Maven Central publishing through the Central Portal. Use when building a library rather than an app, before a release, when deciding whether a change breaks consumers, or when setting up publishing.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
---

Keep an Android library safe to depend on: apps upgrade without compile or runtime breaks, the AAR adds nothing consumers didn't ask for, and every release is signed, documented, and reproducible. This is the deep companion to the always-on `android-library-authoring.md` rule. `android-gradle-architecture-pro` reviews build-logic and convention plugins; `r8-shrink-pro` owns keep-rule syntax and is the authority for `consumer-rules.pro` content. Report only genuine problems.

Pick the mode from the request:

- **Review a change**: classify every public-API and ABI-dump difference (`references/api-and-abi.md`) and name the required version bump.
- **Set up a module**: produce the library `build.gradle.kts`, explicit API, ABI validation, and consumer rules (`references/module-setup.md`).
- **Publish**: wire signing and the Central Portal, POM, sources and docs jars, and the release workflow (`references/publishing.md`).
- **Audit**: run the checklist below over the whole library.

Load only the reference you need:

- `references/module-setup.md` — `com.android.library` configuration, `namespace`, SDK levels without `targetSdk`, `resourcePrefix`, non-transitive R, `aarMetadata`, Kotlin `apiVersion` / `coreLibrariesVersion` floors, `api` vs `implementation`, JVM vs Android vs Multiplatform modules, consumer rules and `lintPublish`, test fixtures and sample apps, Compose libraries.
- `references/api-and-abi.md` — explicit API mode, what breaks source vs binary compatibility in Kotlin, data classes, default parameters and `@JvmOverloads`, sealed and enum growth, inline functions and `@PublishedApi`, `@RequiresOptIn`, Java interop annotations, ABI dumps with binary-compatibility-validator or KGP `abiValidation`, deprecation levels.
- `references/publishing.md` — Maven Central through the Central Portal, namespace verification, signing with in-memory keys, the `com.vanniktech.maven.publish` plugin and plain `maven-publish`, POM requirements, Dokka for docs and Javadoc jars, BOMs, versioning, GitHub Packages for internal libraries, and a release workflow.

## Review Checklist

1. **Module**: `com.android.library`, `namespace`, no `applicationId` or `targetSdk`, `resourcePrefix`, not minified, `consumer-rules.pro` wired.
2. **Floors**: `minSdk`, Kotlin `apiVersion` / `languageVersion`, `coreLibrariesVersion`, and Java bytecode target chosen for consumers, not for the build machine.
3. **Dependencies**: `api` only for types in public signatures; no SNAPSHOT or dynamic versions; nothing pulled in that only the sample uses.
4. **API**: `explicitApi()` on; `internal` by default; no public data classes; experimental API behind `@RequiresOptIn`; Java callers covered.
5. **ABI**: dump committed, CI fails on unreviewed changes, version bump matches the dump diff.
6. **Deprecation**: removals went through `WARNING` → `ERROR` → `HIDDEN` with `ReplaceWith`.
7. **Publishing**: signed, sources and docs jars, complete POM, Gradle Module Metadata, released from CI on a tag.
8. **Docs and samples**: KDoc on every public symbol, Dokka builds, a sample app that uses only the public API.

## Output Format

Organize findings by file. For each issue give the file and lines, the rule broken, the consumer impact (compile break, runtime `NoSuchMethodError`, R8 crash, version conflict), and a before/after fix. For a change review, end with a table of API differences and the required SemVer bump. Finish with a prioritized summary.
