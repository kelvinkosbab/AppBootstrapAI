---
description: ktlint + detekt + Android Lint strategy for Android projects — distinct jobs of each tool, .editorconfig / detekt.yml / lint.xml config, baselines, suppression hygiene, CI placement, version pinning
globs: "**/{*.kt,*.kts,.editorconfig,detekt.yml,detekt-baseline.xml,lint.xml,lint-baseline.xml,build.gradle.kts,build.gradle}"
---

# Android Linting Strategy

Android has **three** linters with **non-overlapping jobs** — using one doesn't cover the others:

- **ktlint** — *formatter + basic style*. Enforces the official Kotlin / Android Kotlin style (indentation, imports, spacing). Mostly auto-fixable (`ktlintFormat`).
- **detekt** — *static analysis*. Complexity, code smells, potential bugs, naming, exception handling. Configurable rulesets; optional type resolution for deeper checks.
- **Android Lint** (`lint` / `lintDebug`) — *Android-specific correctness*. Resource problems, manifest issues, API-level misuse, accessibility gaps, performance, security (hardcoded secrets), unused resources. Ships with AGP; **distinct from the other two**.

A project that runs ktlint but not Android Lint is missing the entire Android-platform check surface. Run all three. For the Gradle plugin wiring + version-catalog setup, see [`android-gradle-conventions.md`](./android-gradle-conventions.md); this rule covers config + discipline.

## ktlint — `.editorconfig`

ktlint reads its config from `.editorconfig` (not a bespoke file):

```ini
# .editorconfig
root = true

[*.{kt,kts}]
ktlint_code_style = android_studio        # or intellij_idea / ktlint_official
ktlint_standard_no-wildcard-imports = enabled
ktlint_standard_filename = enabled
max_line_length = 120
indent_size = 4
insert_final_newline = true
# Disable a specific standard rule project-wide (justify it):
ktlint_standard_function-naming = disabled # Compose @Composables are PascalCase
```

- **`ktlint_code_style`** picks the baseline ruleset. `android_studio` matches the Android Kotlin Style Guide.
- **Compose gotcha:** `@Composable` functions are `PascalCase`, which ktlint's `function-naming` rule flags. Disable that standard rule (as above) or the whole project fights Compose conventions.
- **`ktlintFormat`** auto-fixes; **`ktlintCheck`** verifies (CI). Run format locally, check in CI.

## detekt — `detekt.yml`

```kotlin
// build.gradle.kts
detekt {
    buildUponDefaultConfig = true            // start from detekt's defaults, override selectively
    config.setFrom("$rootDir/config/detekt/detekt.yml")
    baseline = file("$rootDir/config/detekt/detekt-baseline.xml")  // for legacy adoption
}
```

```yaml
# config/detekt/detekt.yml — overrides ON TOP of the default config
complexity:
  LongMethod:
    threshold: 60
  TooManyFunctions:
    thresholdInClasses: 15
  CyclomaticComplexMethod:
    threshold: 15
style:
  MaxLineLength:
    maxLineLength: 120
  ForbiddenComment:
    active: false           # if TODOs live in the issue tracker
# Rules needing type resolution (only fire on the type-resolution task — see below):
potential-bugs:
  active: true
```

- **`buildUponDefaultConfig = true`** is the right baseline — override thresholds, don't redefine the whole ruleset.
- **Don't enable detekt's `formatting` ruleset if you run ktlint separately** — it *is* ktlint, wrapped, and the two will duplicate/conflict. Pick one place for formatting (standalone ktlint is the common choice).
- **Type resolution** — rules like `LateinitUsage`-deeper-checks and many `potential-bugs` rules need the compiler's type info. The plain `detekt` task runs without it (fast, partial); `detektMain` / `detektTest` (or a `detektWithTypeResolution`-style task) run *with* the classpath (slower, complete). Wire the type-resolution task into CI for full coverage.

## Android Lint — `lint {}` + `lint.xml`

```kotlin
// build.gradle.kts (app/library module)
android {
    lint {
        abortOnError = true               // fail the build on errors
        warningsAsErrors = true           // promote warnings → errors in CI
        baseline = file("lint-baseline.xml")
        checkDependencies = true          // also lint library modules from the app
        disable += setOf("ObsoleteLintCustomCheck")
        // Promote a specific check to error severity:
        error += setOf("StopShip", "HardcodedText")
    }
}
```

```xml
<!-- lint.xml — per-rule, per-path severity overrides -->
<lint>
    <issue id="MissingTranslation" severity="ignore" />
    <issue id="HardcodedText" severity="error" />
    <issue id="UnusedResources">
        <ignore path="src/debug/**" />
    </issue>
</lint>
```

- **`lintDebug` (or `lint`)** is the task. Running only `lintRelease` is a common miss — debug-variant issues go unchecked.
- **`warningsAsErrors = true` in CI** but consider leaving it off locally so day-to-day builds aren't blocked by every warning.
- **`checkDependencies = true`** in the app module lints your library modules transitively — otherwise per-module issues hide.
- **Security/correctness checks worth promoting to `error`:** `HardcodedText`, `StopShip`, `MissingPermission`, exported-component issues.

## Baselines (Legacy Adoption)

Both detekt and Android Lint support baseline files — snapshot the *existing* issues so the gate only fails on *new* ones:

```bash
./gradlew detektBaseline      # writes detekt-baseline.xml
./gradlew updateLintBaseline  # writes lint-baseline.xml (AGP 7+)
```

- **Generate once, then burn it down** — a baseline is a debt ledger, not a permanent silencer. Track its size; it should shrink over releases.
- **Never regenerate the baseline to "fix" a failing CI** — that re-snapshots new issues into the accepted set, defeating the gate. Fix the issue or suppress it explicitly with a justification.
- ktlint has no baseline; use `.editorconfig` per-path rule disables + `ktlintFormat` to get clean fast.

## Suppression Hygiene

Suppress at the **smallest scope** with a **reason**:

```kotlin
// detekt + Kotlin compiler warnings — scope to the element, not the file.
@Suppress("LongMethod") // generated builder; splitting hurts readability
fun build(): Config { … }

// Android Lint — @SuppressLint, scoped to the member.
@SuppressLint("HardcodedText") // debug-only diagnostics screen
fun debugLabel() = "RAW DUMP"

// ktlint — disable a standard rule for a block via @Suppress:
@Suppress("ktlint:standard:no-wildcard-imports")
import com.example.generated.*
```

- **Never `@file:Suppress(...)` as a shortcut** — it hides every instance in the file, including future ones.
- **`tools:ignore` in XML** for any remaining XML resources (rare in Compose-first projects).
- **Every suppression gets a comment** explaining why the rule doesn't apply here.

## Triage — What To Do When a Rule Fires

A finding is a question, not a verdict — and across three linters the answer is *usually* "fix it." When it isn't, follow the order of preference below. Reaching past the top to silence a finding is how a config rots into noise the team ignores.

**Per-finding decision order (prefer earlier):**

1. **Fix the code.** The default, and the only response that improves the codebase. The linter is right more often than your gut says.
2. **Tune the rule** — when the rule is *valuable* but its *threshold/severity* is wrong for this project. detekt: adjust thresholds in `detekt.yml` (`LongMethod`, `CyclomaticComplexMethod`, `MaxLineLength`). Android Lint: set severity in `lint.xml` or the `lint {}` block. ktlint: toggle a `ktlint_standard_*` rule in `.editorconfig`. **Once, globally** — one config edit beats N `@Suppress`es.
3. **Suppress at the call site** — `@Suppress("RuleId")` / `@SuppressLint("CheckId")` scoped to the smallest element, with a reason — when *this one instance* is a justified exception but the rule is right in general.
4. **Disable the rule project-wide** — only when the rule is *wrong for the whole codebase* (e.g., `function-naming` vs. Compose `@Composable` PascalCase). Rare. Do it in `.editorconfig` / `detekt.yml` / `lint.xml` with a comment saying why.

Never invert this. Disabling a rule to clear one finding throws away its value everywhere else.

**ktlint mostly skips triage.** Almost every ktlint finding is auto-fixable — run `./gradlew ktlintFormat` and it's gone. Triage is really about detekt and Android Lint, where findings need a human decision.

**Prioritizing a backlog** (turning the linters on existing code — work it in tiers):

- **Tier 1 — correctness + security.** Android Lint's `HardcodedText` (in security-sensitive contexts), `MissingPermission`, exported-component issues, `StopShip`; detekt's `potential-bugs` ruleset. Promote to `error`; fix now.
- **Tier 2 — bug-prone smells.** detekt complexity/dead-code; Android Lint performance + correctness warnings. Fix where cheap; **baseline** the rest (`detekt-baseline.xml`, `lint-baseline.xml`) so the gate only fails on *new* issues.
- **Tier 3 — formatting/style.** ktlint owns this — `ktlintFormat` clears it. No backlog.

**Baseline discipline (the Android backlog tool):** a baseline is a **debt ledger, not a silencer**. Generate it once, then **burn it down** over releases — track its line count; it should shrink. **Never regenerate a baseline to make a failing CI pass** — that re-snapshots the *new* issue into the accepted set and defeats the gate. Fix the new finding or suppress it explicitly with a reason.

**Anti-patterns:**

- **Regenerating the baseline to silence CI** — re-accepts new debt. The single worst linting habit on Android.
- **Blanket-disabling a rule to go green** — deleting the rule, dressed up.
- **`@file:Suppress` / `abortOnError = false`** as backlog shortcuts — both hide everything, including future violations.
- **Suppressing without a reason comment.**
- **Treating all findings as equal** — a hardcoded secret and a long method are not the same tier.

## CI Placement

All three are blocking checks; the local loop is lighter:

```bash
# Local (fast, auto-fixing)
./gradlew ktlintFormat

# CI (the authoritative gate — all three)
./gradlew ktlintCheck detekt lintDebug
```

- **Order doesn't matter, but run all three.** Many projects forget `lintDebug` and ship Android-specific bugs ktlint/detekt can't see.
- **Pin all three versions** via the version catalog (`gradle/libs.versions.toml`) — see `android-gradle-conventions.md`. An unpinned plugin bump can turn CI red with no code change.
- For multi-module builds, apply the plugins via a `build-logic` convention plugin so config doesn't drift per-module.

## Common Pitfalls

- **Running only ktlint** — misses detekt's bug/complexity analysis AND all of Android Lint's platform checks. Three tools, three jobs.
- **detekt `formatting` ruleset + standalone ktlint** — duplicate/conflicting formatting. Pick one.
- **Only `lintRelease` wired** — debug-variant issues never checked. Use `lintDebug` (or `lint` for all variants).
- **Baseline regenerated to silence CI** — re-snapshots new issues as accepted. Fix or suppress explicitly instead.
- **`@file:Suppress`** as a blanket — hides future violations too.
- **Compose `function-naming` fighting ktlint** — disable the standard rule; `@Composable`s are PascalCase by convention.
- **`abortOnError = false` left on** — Android Lint runs but never fails the build; findings rot.
- **Unpinned plugin versions** — a `ktlint`/`detekt`/AGP bump changes the rule set and breaks CI with no source change.
- **detekt without type resolution in CI** — silently skips the rules that need the classpath (a large chunk of the bug-finding value).

## Patterns to Follow

```ini
# .editorconfig
root = true
[*.{kt,kts}]
ktlint_code_style = android_studio
max_line_length = 120
ktlint_standard_function-naming = disabled   # Compose @Composables are PascalCase
```

```kotlin
// build.gradle.kts — all three linters configured
detekt {
    buildUponDefaultConfig = true
    config.setFrom("$rootDir/config/detekt/detekt.yml")
    baseline = file("$rootDir/config/detekt/detekt-baseline.xml")
}

android {
    lint {
        abortOnError = true
        warningsAsErrors = true               // CI; consider false locally
        baseline = file("lint-baseline.xml")
        checkDependencies = true
        error += setOf("HardcodedText", "StopShip")
    }
}
```

```yaml
# CI — all three as blocking checks
- run: ./gradlew ktlintCheck detekt lintDebug
```
