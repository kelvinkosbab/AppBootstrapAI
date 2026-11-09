---
description: Enforce Android project conventions — Kotlin, Jetpack Compose, MVVM, Hilt, Retrofit/Moshi
globs: "**/*.{kt,kts}"
paths:
  - "**/*.{kt,kts}"
must:
  - "Kotlin and Jetpack Compose only, MVVM with Hilt, and `StateFlow` collected with `collectAsStateWithLifecycle()`."
  - "Never hardcode secrets; all UI text in `strings.xml`."
  - "Run `./gradlew ktlintCheck` before committing; no wildcard imports."
---

# Android Project Rules

## Architecture & Stack

- Use **MVVM** architecture.
- UI: **Jetpack Compose** only (no XML unless specified).
- Use Jetpack Compose and MVVM for all new UI features.
- DI: **Hilt** (use `@HiltViewModel` and `@Inject`).
- State: Use `StateFlow` in ViewModels; `collectAsStateWithLifecycle()` in UI.
- Ensure all ViewModels use Hilt `@HiltViewModel` and `StateFlow` for state management.
- Networking: **Retrofit** + **Moshi**.

## Code Style

- Language: **Kotlin**.
- Formatting: Follow **ktlint** standards.
- Naming: `PascalCase` for `@Composable`s, `camelCase` for variables/functions.
- No wildcard imports.

## Development Workflow

- Build: `./gradlew assembleDebug`
- Test: `./gradlew test`
- Lint: `./gradlew ktlintCheck`
- Run `./gradlew ktlintCheck` before every commit to ensure formatting matches project standards.

## Android CLI (agents)

When the [Android CLI](https://developer.android.com/tools/agents/android-cli) (`android`) is on `PATH`, prefer it to guessing:

- **Check fast-moving APIs** with `android docs search "<keywords>"`, then `android docs fetch <kb:// url>`, before you write code from memory (AGP, Compose, Navigation, Play policy).
- **Navigate code** with `android studio check`. If it reports a connected project, use `android studio find-declaration`, `find-usages`, and `analyze-file` rather than text search, and `render-compose-preview` to check Compose UI. Run `android help studio` for arguments.
- **Set up and run** with `android sdk install` (only the components needed), `android emulator`, and `android run`.
- **Official Android skills** ([android/skills](https://github.com/android/skills)) install with `android skills add <name>` or `--all`. Re-running `add` overwrites an installed skill, so rename any skill you customize.
- Without the CLI, fall back to `./gradlew` and `adb`.

## Safety

- Never hardcode API keys or secrets.
- Always use `strings.xml` for UI text; no hardcoded strings in `@Composable`s.
