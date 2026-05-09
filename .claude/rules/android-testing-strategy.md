---
description: Test strategy and coverage discipline for Android — unit/instrumentation/UI levels, Compose testing, Flow testing with Turbine, Hilt test modules, MockK, and JaCoCo coverage gates
globs: "**/*.{kt,kts}"
---

# Android Testing Strategy & Coverage

This rule answers *what* to test, *where* it lives, and *how much* coverage is enough on Android.

## Test Pyramid & Source Sets

- **Unit tests** (`src/test/`) — bulk of the suite. JUnit 4 or 5, MockK, Turbine for `Flow`, `runTest` for coroutines. Robolectric only when you genuinely need an Android shadow (e.g., Resources, SharedPreferences).
- **Instrumentation tests** (`src/androidTest/`) — fewer. Run on a device/emulator. Compose UI tests, Hilt-injected component tests, integration with real Room/SQLite.
- **UI tests** — fewest. Compose UI tests via `createComposeRule()` / `createAndroidComposeRule()`; Espresso for any remaining XML screens.

Run subsets via Gradle: `./gradlew :feature:foo:test`, `./gradlew :feature:foo:connectedAndroidTest`.

## What to Test

- **Pure functions** — every meaningful branch and edge case.
- **ViewModel public surface** — `StateFlow<UiState>` transitions, intent handlers, error paths.
- **Repository / data layer** — happy path, error mapping, dispatcher boundaries.
- **State emissions over time** — Turbine `.test { awaitItem(); awaitComplete() }` for `Flow`/`StateFlow`.
- **Compose semantics** — `onNodeWithTag` / `onNodeWithContentDescription` assertions for the actual a11y surface real users (and TalkBack) see.

## What NOT to Test

- **Hilt module wiring** — test the things modules provide, not the `@Module` itself.
- **Generated code** — KSP/KAPT outputs, Hilt-generated factories, Room-generated DAOs (test the queries you wrote, not the trampoline code).
- **Activity / Application classes** — keep them thin; test what they call into.
- **Compose previews** (`@Preview` functions) — they exist for Android Studio.
- **Third-party libraries** — mock at *your* boundary, not theirs.

## Naming Conventions

- File: `<TypeName>Test.kt` next to source, or under `src/test/.../<package>/`.
- Class: `class <TypeName>Test`.
- Method: backticked descriptive names — `` `state emits Loading then Loaded`() ``. Reads cleanly in failure output and avoids the `testFoo()` ambiguity.
- Group with `@Nested` classes when one type has several behavior clusters.

## Coroutines Testing

- **`runTest { }`** for any test that suspends. Don't use `runBlocking` — it doesn't give you virtual time.
- **Inject dispatchers.** ViewModels and repositories take `CoroutineDispatcher` parameters (qualified `@IoDispatcher`, `@DefaultDispatcher`); tests substitute `UnconfinedTestDispatcher` (eager) or `StandardTestDispatcher` (controlled timing).
- **`StandardTestDispatcher` + `advanceTimeBy()` / `runCurrent()`** for timing-sensitive code (debounce, retry-with-backoff).
- **Don't catch `CancellationException`** in tests any more than in production — let it propagate.
- **`Dispatchers.Main` in tests:** install with `Dispatchers.setMain(testDispatcher)` in `@Before`, reset with `Dispatchers.resetMain()` in `@After`. Prefer a JUnit rule (`MainDispatcherRule`) so it's not boilerplate per file.

## Flow / StateFlow Testing with Turbine

Turbine (`app.cash.turbine`) is the Android idiom for asserting on `Flow` emissions over time:

```kotlin
@Test
fun `state emits Loading then Loaded`() = runTest {
    val repo = mockk<FeedRepository>()
    coEvery { repo.fetch() } returns Result.success(items)

    val viewModel = FeedViewModel(repo, ioDispatcher = UnconfinedTestDispatcher())

    viewModel.state.test {
        assertEquals(FeedState.Loading, awaitItem())
        viewModel.refresh()
        assertEquals(FeedState.Loaded(items), awaitItem())
        cancelAndIgnoreRemainingEvents()
    }
}
```

- **Always close the flow** with `awaitComplete()`, `cancelAndIgnoreRemainingEvents()`, or `expectNoEvents()`. Leaving a `.test { }` block with unclaimed emissions throws.
- **`expectNoEvents()`** to assert that nothing emits for a window — useful for debounce and back-pressure tests.
- **Don't use `.collect { }` directly in tests** — you can't assert progressively. Turbine is what makes this ergonomic.

## Compose UI Testing

- **Locate by semantics, not by visible text.** `onNodeWithTag("submit_button")`, `onNodeWithContentDescription(...)`. Visible-text locators break the moment you ship a new locale.
- **`Modifier.testTag("submit_button")`** is the test-time hook; pair with `mergeDescendants` for compound rows so the merged node is what tests see.
- **`composeTestRule.setContent { ... }`** mounts the Composable; assert with `assertIsDisplayed()`, `assertHasClickAction()`, `assertTextContains(...)`.
- **No `Thread.sleep()`.** Use `composeTestRule.waitForIdle()` for "let recomposition settle," `waitUntil(timeoutMillis) { /* predicate */ }` for state-driven waits.
- **Test the a11y surface** — semantics-driven tests double as accessibility regression tests.

## Hilt Test Modules

- **`@HiltAndroidTest`** on the test class; `@get:Rule val hiltRule = HiltAndroidRule(this)` and `hiltRule.inject()` in `@Before`.
- **`HiltTestApplication`** as the test app via `@CustomTestApplication` or a `MyTestRunner : AndroidJUnitRunner`.
- **`@UninstallModules(...)` + `@BindValue`** to swap real bindings for test fakes:

  ```kotlin
  @UninstallModules(NetworkModule::class)
  @HiltAndroidTest
  class FeedRepositoryTest {
      @BindValue val api: FeedApi = FakeFeedApi()
      // ...
  }
  ```

- **Don't reach into the production Hilt graph** to pull out internals — bind a fake or test-double at the same boundary the real module binds.

## MockK

- **`mockk<T>()`** for interfaces and open classes; `mockk<T>(relaxed = true)` only when you're *deliberately* ignoring most calls and explicit about it.
- **`coEvery { repo.fetch() } returns ...`** for suspend functions (note the `co` prefix); `every { ... }` for sync.
- **`verify { mock.method(any()) }` / `coVerify`** to assert side effects. `verify(exactly = 0) { ... }` for "this should not have been called."
- **Don't mock data classes.** Construct them with test data — `User(id = "test", name = "Test")` or a `User.fixture()` factory.
- **Avoid `every { obj.foo } returns bar` chains for property reads on real classes** — use a real subclass or fake.

## Fixtures

- Static factory functions on companion objects or top-level test helpers:

  ```kotlin
  fun userFixture(
      id: String = "test-id",
      name: String = "Test"
  ) = User(id = id, name = name)
  ```

- Avoids the `mockk<User>()` anti-pattern for value types.

## Coverage

- **JaCoCo** (`./gradlew jacocoTestReport`) is the standard. Configure once at the project level; per-module reports merged in CI.
- **Set a CI gate** as a policy decision — typical Android projects land at 70–80% line coverage. Pick what your team actually maintains; a wishful 90% that everyone routes around is worse than 70% that holds.
- **Exclude from coverage**:
  - Generated code: `**/dagger/**`, `**/hilt_aggregated_deps/**`, `**/*_HiltModules*`, `**/*Factory*`, KSP outputs.
  - Activity / Application / `@HiltAndroidApp` classes (delegate to ViewModels — those are tested).
  - Compose `@Preview` functions.
  - Auto-generated Room DAOs (test queries via real DAO calls, not the generated impl).
  - DI modules (`@Module`-annotated classes with only `@Provides` factories).
- **Don't game it.** A line covered by a test that asserts nothing is *worse* than an uncovered line — false confidence. Code-review tests, not just coverage deltas.

## Common Pitfalls

- **Order-dependent tests** — JUnit 5 randomizes by default; ensure tests stand alone.
- **`runBlocking` in app-code tests** — use `runTest` for virtual time and structured cancellation.
- **Dispatchers not reset** — `Dispatchers.setMain` without a corresponding `resetMain` leaks across tests. Use a `MainDispatcherRule`.
- **Compose tests using visible text** — fragile across locales. Use `testTag` / `contentDescription`.
- **`Thread.sleep()` anywhere** — replace with `waitForIdle` / `waitUntil` / virtual time.
- **Real network in unit tests** — even pointing at a "test" environment makes tests flaky and slow. Use `MockWebServer` or fake repositories.
- **Mocking Android framework classes (`Context`, `Resources`)** when you could use Robolectric — Robolectric gives you real-ish behavior; mocked `Context` papers over bugs.
- **Coverage threshold set, but the report ignored** — wire it into CI as a *failing* gate, or it's decorative.

## Patterns to Follow

```kotlin
// MainDispatcherRule — reusable across the suite
@OptIn(ExperimentalCoroutinesApi::class)
class MainDispatcherRule(
    val testDispatcher: TestDispatcher = StandardTestDispatcher()
) : TestWatcher() {
    override fun starting(description: Description) = Dispatchers.setMain(testDispatcher)
    override fun finished(description: Description) = Dispatchers.resetMain()
}

// ViewModel test — runTest, MockK, Turbine, injected dispatcher
@OptIn(ExperimentalCoroutinesApi::class)
class FeedViewModelTest {

    @get:Rule val mainDispatcherRule = MainDispatcherRule()

    private val repo = mockk<FeedRepository>()
    private lateinit var viewModel: FeedViewModel

    @Before
    fun setUp() {
        viewModel = FeedViewModel(
            repo,
            ioDispatcher = mainDispatcherRule.testDispatcher
        )
    }

    @Test
    fun `refresh emits Loading then Loaded`() = runTest {
        coEvery { repo.fetch() } returns Result.success(listOf(itemFixture()))

        viewModel.state.test {
            assertEquals(FeedState.Loading, awaitItem())
            viewModel.refresh()
            assertEquals(FeedState.Loaded(listOf(itemFixture())), awaitItem())
            cancelAndIgnoreRemainingEvents()
        }
    }
}

// Compose UI test — semantics-driven, no visible-text locators
class FeedScreenTest {
    @get:Rule val composeTestRule = createComposeRule()

    @Test
    fun retryButton_isVisible_whenStateIsError() {
        composeTestRule.setContent {
            FeedScreen(state = FeedState.Error("boom"), onRetry = {})
        }
        composeTestRule.onNodeWithTag("retry_button").assertIsDisplayed()
    }
}
```
