---
description: Enforce Android project conventions — Kotlin, Jetpack Compose, MVVM, Hilt, Retrofit/Moshi
globs: "**/*.{kt,kts}"
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

## Safety

- Never hardcode API keys or secrets.
- Always use `strings.xml` for UI text; no hardcoded strings in `@Composable`s.
