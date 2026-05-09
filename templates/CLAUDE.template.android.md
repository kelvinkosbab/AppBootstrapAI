# CLAUDE.md

<!--
  This file is the single most important onboarding doc for Claude Code. It is
  loaded at the start of every session in this repo. Keep it current, concrete,
  and short — Claude reads it, not your README.

  Replace every <PLACEHOLDER> below, and delete sections that don't apply.
  Delete this comment block when you're done.
-->

## Project Overview

<PROJECT_NAME> is <ONE_SENTENCE_DESCRIPTION>. <APPLICATION_ID>.

- Platform: Android
- Min SDK: <e.g., 26>
- Target SDK: <e.g., 34>
- Compile SDK: <e.g., 34>
- Language: Kotlin <2.x>
- Compose BOM: <version>

## Build & Run

```bash
./gradlew assembleDebug          # build the debug APK
./gradlew installDebug           # install to a connected device/emulator
./gradlew test                   # unit tests
./gradlew connectedAndroidTest   # instrumentation tests
./gradlew ktlintCheck            # lint (run before every commit)
./gradlew ktlintFormat           # auto-fix lint issues
./gradlew detekt                 # static analysis (if configured)
```

## Architecture

- UI: **Jetpack Compose** (no XML for new screens)
- Pattern: **MVVM**
- DI: **Hilt** (`@HiltViewModel`, `@Inject`, `@Module`)
- State: **`StateFlow`** in ViewModels, **`collectAsStateWithLifecycle()`** in Composables
- Async: **Kotlin coroutines** (`viewModelScope`, `lifecycleScope`)
- Networking: **Retrofit** + **Moshi** (or **kotlinx.serialization**)
- Persistence: <Room / DataStore / proto-DataStore / none>
- Image loading: <Coil / Glide>
- Navigation: <Navigation-Compose / Decompose / custom>

## Module Graph

<!-- If your project has more than one Gradle module, list them. Delete if single-module. -->

| Module | Type | Purpose |
|--------|------|---------|
| `:app` | application | Entry point, DI graph wiring |
| `:feature:<name>` | library | <feature> screens + view models |
| `:data` | library | Repositories, network, persistence |
| `:core:<name>` | library | <shared utilities> |

## Code Conventions

- Formatting: **ktlint** (no exceptions). Run `./gradlew ktlintFormat` before every commit.
- Composables: `PascalCase`. Top-level functions: `camelCase`.
- No wildcard imports.
- All user-facing strings come from `strings.xml` via `stringResource(R.string.…)` — including `contentDescription`, `stateDescription`, error messages.
- One Composable per file when the file gets large; group small private helpers with their parent Composable.

## Coroutines

(Enforced via `.claude/rules/android-coroutines-best-practices.md`. Project specifics:)

- Default dispatchers are injected via Hilt: `@IoDispatcher`, `@DefaultDispatcher`, `@MainDispatcher`.
- ViewModels expose `StateFlow<UiState>` (read-only); internal mutation via `_state.update { ... }`.
- One-shot events are `SharedFlow<UiEvent>` with `replay = 0`.
- <Project-specific patterns — e.g., a custom scope, a base ViewModel>

## Compose

(Enforced via `.claude/rules/android-compose-best-practices.md`. Project specifics:)

- Always `collectAsStateWithLifecycle()`, never raw `collectAsState()`.
- Stateless Composables receive `value` + `onValueChange`; stateful wrappers read from the ViewModel and forward.
- Stable / immutable types: <where you've annotated `@Stable` / `@Immutable`>
- <Theme module name and how to use `MaterialTheme` overrides>

## Hilt / DI

- App-level component: `@HiltAndroidApp class MyApp : Application()`
- Activity: `@AndroidEntryPoint`
- ViewModel: `@HiltViewModel`
- Modules live in: <`:app/src/main/java/.../di/`>
- Dispatcher qualifiers: `@IoDispatcher`, `@DefaultDispatcher`, `@MainDispatcher` (defined in <module>)

## Testing

- Framework: <JUnit 5 / JUnit 4 with `@RunWith(MockitoJUnitRunner::class)`>
- Coroutines: `runTest`, `StandardTestDispatcher` / `UnconfinedTestDispatcher`
- `Flow` testing: **Turbine** (`flow.test { awaitItem(); awaitComplete() }`)
- Compose UI tests: `createComposeRule()`, `onNodeWithText`, `onNodeWithTag`
- Robolectric: <yes/no — what for>
- Run subset: `./gradlew :feature:<name>:test`

## Resources & Localization

- All user-facing text in `strings.xml`; supported locales: <en, ...>
- Dimensions: `dp` for layout, `sp` for text sizes.
- Colors via `MaterialTheme.colorScheme` — never hardcode `Color(0xFF...)` in feature code.
- Drawables: prefer vector (`<vector>`) over raster.

## CI / GitHub Actions

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| <android.yml> | Push + PR to main | Build, test, ktlint |

## Important Gotchas

<!-- The things that took you a day to figure out and don't want to re-explain. -->

- <e.g., A specific minSdk feature gate>
- <e.g., A ProGuard/R8 keep rule that's load-bearing>
- <e.g., A flavor-specific resource override>
- <e.g., Compose BOM version that conflicts with `lifecycle-runtime-compose`>

## AI Rules and Skills

This repo uses the AppBootstrapAI bundle in `.claude/`:

- **Rules** (`.claude/rules/`) auto-apply to matching files. See each rule's `globs:` for scope.
- **Skills** (`.claude/skills/`) fire on demand. *(Note: Android-side skills are on the roadmap; the bundle currently ships rules for Android, skills for Apple.)*
- Local permission overrides go in `.claude/settings.local.json` (git-ignored).

When you discover a new pattern that should be enforced project-wide, add it to `.claude/rules/<name>.md` with `description:` and `globs:` frontmatter. Keep rules short and prescriptive.
