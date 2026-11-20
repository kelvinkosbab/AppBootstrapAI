# Publishing Android and Kotlin Libraries

## Where to publish

| Destination | Use for | Notes |
|---|---|---|
| **Maven Central** via the Central Portal (`central.sonatype.com`) | Public libraries | OSSRH (`s01.oss.sonatype.org`) was shut down in 2025; publish through the Portal. Needs a verified namespace (your reverse domain, or `io.github.<user>`). |
| **Google Maven** | Google only | Not available to third parties. |
| **GitHub Packages** / Artifactory / a cloud registry | Internal libraries | Consumers need credentials even for reads on GitHub Packages; fine inside one org. |
| **JitPack** | Experiments | Builds on demand from a git tag; not reproducible or signed by you. Don't make production apps depend on it. |
| `mavenLocal()` | Local testing only | Never a consumer's repository in CI. |

## Coordinates and versions

- `group` is your verified namespace (`com.example.widgets`), `artifactId` per module (`widgets-core`, `widgets-compose`), one shared `version` for all modules of a release.
- SemVer: `1.4.0`, pre-releases `2.0.0-alpha01` / `2.0.0-beta.1` / `2.0.0-rc.1`. Never re-publish a version; Central doesn't allow it, and caches everywhere already hold the first one.
- Version comes from the git tag in CI (`-PVERSION_NAME=${GITHUB_REF_NAME}`), not a constant edited by hand.

## Option A: `com.vanniktech.maven.publish` (recommended)

The plugin configures Android, JVM, and Multiplatform publications, sources and Javadoc jars, signing, and Central Portal upload with one block.

```kotlin
// widgets/build.gradle.kts
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.dokka)
    alias(libs.plugins.dokka.javadoc)
    alias(libs.plugins.vanniktech.maven.publish)
}

mavenPublishing {
    publishToMavenCentral(automaticRelease = false) // stage, then release from the Portal UI (or true once trusted)
    signAllPublications()
    coordinates("com.example.widgets", "widgets-core", providers.gradleProperty("VERSION_NAME").get())

    pom {
        name = "Widgets Core"
        description = "Reusable widgets for Android apps."
        inceptionYear = "2026"
        url = "https://github.com/example/widgets"
        licenses {
            license {
                name = "The Apache License, Version 2.0"
                url = "https://www.apache.org/licenses/LICENSE-2.0.txt"
                distribution = "repo"
            }
        }
        developers {
            developer { id = "example"; name = "Example Inc."; url = "https://github.com/example" }
        }
        scm {
            url = "https://github.com/example/widgets"
            connection = "scm:git:git://github.com/example/widgets.git"
            developerConnection = "scm:git:ssh://git@github.com/example/widgets.git"
        }
    }
}
```

Publish from CI:

```bash
./gradlew publishToMavenCentral --no-configuration-cache
```

The plugin's API has changed across major versions (the `SonatypeHost` argument went away once the Portal became the only host); check its docs for the version you pin.

## Option B: plain `maven-publish` + `signing`

```kotlin
android {
    publishing {
        singleVariant("release") {
            withSourcesJar()
            withJavadocJar()
        }
    }
}

publishing {
    publications {
        register<MavenPublication>("release") {
            groupId = "com.example.widgets"
            artifactId = "widgets-core"
            version = providers.gradleProperty("VERSION_NAME").get()
            afterEvaluate { from(components["release"]) }
            pom { /* same fields as above */ }
        }
    }
    repositories {
        maven {
            name = "staging"
            url = uri(layout.buildDirectory.dir("staging-repo"))
        }
    }
}

signing {
    useInMemoryPgpKeys(
        providers.environmentVariable("SIGNING_KEY").orNull,
        providers.environmentVariable("SIGNING_PASSWORD").orNull,
    )
    sign(publishing.publications)
}
```

Then zip the staging repository and upload it with the Central Portal's publisher API (or use JReleaser). Option A does all of this for you; choose B only when you need full control.

## Central requirements

Central validates every deployment and rejects it if any of these are missing:

- POM with `name`, `description`, `url`, `licenses`, `developers`, `scm`.
- A `-sources.jar` and a `-javadoc.jar` for every JAR/AAR (the Javadoc jar may be Dokka HTML).
- A `.asc` signature for every file, made with a key whose public half is on a public keyserver (`keys.openpgp.org`, `keyserver.ubuntu.com`).
- Checksums (`.md5`, `.sha1`; the tooling generates them).
- Group ID inside a namespace you verified in the Portal.

## Secrets

Generate a Portal user token (not your login password) and a dedicated signing subkey. In CI, store:

| Secret | Gradle property (vanniktech) |
|---|---|
| Portal token username | `ORG_GRADLE_PROJECT_mavenCentralUsername` |
| Portal token password | `ORG_GRADLE_PROJECT_mavenCentralPassword` |
| ASCII-armored private key | `ORG_GRADLE_PROJECT_signingInMemoryKey` |
| Key ID (last 8 hex digits) | `ORG_GRADLE_PROJECT_signingInMemoryKeyId` |
| Key passphrase | `ORG_GRADLE_PROJECT_signingInMemoryKeyPassword` |

Never commit keys or put them in `gradle.properties` in the repo; a developer's `~/.gradle/gradle.properties` is fine for local test publishing.

## Docs with Dokka

- Dokka 2 (`org.jetbrains.dokka`, Gradle plugin v2 mode): `./gradlew dokkaGenerate` writes HTML; `org.jetbrains.dokka-javadoc` produces the Javadoc-format output used for `-javadoc.jar`.
- Aggregate multi-module docs from the root (`dependencies { dokka(project(":widgets-core")) }`) and publish them to GitHub Pages per release.
- Add `externalDocumentationLinks` for AndroidX so `[Activity]` and `[Modifier]` resolve (`android-documentation-strategy.md`).
- Suppress internal packages (`perPackageOption { matchingRegex = ".*\\.internal.*"; suppress = true }`).

## BOM for multi-artifact libraries

```kotlin
// widgets-bom/build.gradle.kts
plugins { `java-platform`; alias(libs.plugins.vanniktech.maven.publish) }

dependencies {
    constraints {
        api(project(":widgets-core"))
        api(project(":widgets-compose"))
    }
}
```

Consumers write `implementation(platform("com.example.widgets:widgets-bom:1.4.0"))` and omit versions on the rest.

## Release workflow

```yaml
name: Release
on:
  push:
    tags: ["[0-9]+.[0-9]+.[0-9]+*"]

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions: { contents: write }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: 17 }
      - uses: gradle/actions/setup-gradle@v4
      - name: Check
        run: ./gradlew check apiCheck   # tests, lint, ABI dump
      - name: Publish
        run: ./gradlew publishToMavenCentral -PVERSION_NAME=${GITHUB_REF_NAME} --no-configuration-cache
        env:
          ORG_GRADLE_PROJECT_mavenCentralUsername: ${{ secrets.MAVEN_CENTRAL_USERNAME }}
          ORG_GRADLE_PROJECT_mavenCentralPassword: ${{ secrets.MAVEN_CENTRAL_PASSWORD }}
          ORG_GRADLE_PROJECT_signingInMemoryKey: ${{ secrets.SIGNING_KEY }}
          ORG_GRADLE_PROJECT_signingInMemoryKeyId: ${{ secrets.SIGNING_KEY_ID }}
          ORG_GRADLE_PROJECT_signingInMemoryKeyPassword: ${{ secrets.SIGNING_PASSWORD }}
      - name: GitHub Release
        run: gh release create "$GITHUB_REF_NAME" --notes-file <(./scripts/changelog-section.sh "$GITHUB_REF_NAME")
        env: { GH_TOKEN: "${{ github.token }}" }
```

`scripts/changelog-section.sh` is a placeholder for whatever extracts the version's section from `CHANGELOG.md`.

## Release checklist

1. `main` green: tests on lowest and newest API, lint, `apiCheck`, sample app build.
2. ABI dump diff since the last tag reviewed; version bump matches (added only → MINOR, anything removed or changed → MAJOR).
3. CHANGELOG `[Unreleased]` moved under the version with today's date.
4. Kotlin, `minSdk`, `minCompileSdk`, and Java target floors unchanged, or the change called out.
5. Tag `X.Y.Z`; CI publishes; release the staged deployment in the Portal if not automatic.
6. Verify: a scratch project resolves the new version from Central and builds (Central can take a while to sync).
7. Publish Dokka docs and the GitHub Release notes.

## Gotchas

- **Deployment rejected for missing Javadoc jar**: Android publications don't make one unless `withJavadocJar()` or the vanniktech plugin with Dokka is configured.
- **Signature fails in CI only**: the key was exported without `--armor`, or newlines were lost in the secret. Store the armored key as-is and pass it through an environment variable.
- **POM shows `project` dependencies as `unspecified`**: every module in the dependency chain needs the same publishing setup and version.
- **Configuration cache**: some publish tasks don't support it yet; pass `--no-configuration-cache` for the publish step only.
- **Consumers get a newer Kotlin stdlib than expected**: `coreLibrariesVersion` wasn't set, so the POM declares the build's stdlib version.
