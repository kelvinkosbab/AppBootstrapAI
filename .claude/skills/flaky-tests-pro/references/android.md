# Flaky Tests on Android

Reproduction tools and fixes for JVM unit tests, Robolectric, Compose UI tests, and Espresso. Google's guide, [Big test stability](https://developer.android.com/training/testing/instrumented-tests/stability), is the official baseline: configure devices so the OS doesn't interrupt tests, synchronize instead of sleeping, and retry only while also fixing.

## Reproduce

JVM unit tests have no built-in repeat flag. Options:

```kotlin
// JUnit 5: temporary, while reproducing.
@RepeatedTest(200)
fun refreshShowsItems() = runTest { … }
```

```bash
# Any JUnit version: loop the one test and count failures.
for i in $(seq 1 100); do
  ./gradlew :feature:feed:impl:testDebugUnitTest \
    --tests "*.FeedViewModelTest.refreshShowsItems" --rerun -q || echo "FAIL $i"
done
```

`--rerun` forces Gradle to run the task again instead of reusing an up-to-date result. Remove `@RepeatedTest` once the flake is fixed.

Instrumented tests:

```bash
./gradlew :app:connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=com.example.FeedScreenTest#showsItems
# Or loop on an installed test APK directly:
adb shell am instrument -w -e class com.example.FeedScreenTest#showsItems \
  com.example.test/androidx.test.runner.AndroidJUnitRunner
```

Run on the same device image CI uses (a Gradle Managed Device, below), with the same parallelism (`maxParallelForks`, sharding). Order problems: JUnit 5 `@TestMethodOrder(MethodOrderer.Random::class)`.

## Coroutines and Flow

- Every dispatcher the code uses is injected; tests pass the `runTest` scheduler's `StandardTestDispatcher`. One leftover `Dispatchers.IO` runs on a real thread and races the assertion.
- `Dispatchers.setMain(testDispatcher)` in a `MainDispatcherRule`, with `resetMain()` in `finished`, or tests that follow inherit a dead dispatcher.
- `runTest` has a default timeout that fails hung tests; raise it per test with `runTest(timeout = …)` only for slow, bounded work.
- `advanceUntilIdle()` doesn't finish infinite flows or `stateIn(WhileSubscribed)` collectors; collect with Turbine (`test { awaitItem() … cancelAndIgnoreRemainingEvents() }`) or `backgroundScope`.

## Robolectric

- The default `@LooperMode(PAUSED)` queues main-looper work. Call `shadowOf(Looper.getMainLooper()).idle()` before asserting on posted work.
- Robolectric runs in one JVM per fork; static state leaks between test classes in the same fork. Reset singletons in setup.

## Compose UI tests

- Compose synchronizes with recomposition automatically, but not with your own async work. Wait on the UI state: `composeTestRule.waitUntil(timeoutMillis = 5_000) { … }`, or `waitUntilExactlyOneExists(hasTestTag("feed_item"))`, `waitUntilAtLeastOneExists`, `waitUntilDoesNotExist`, `waitUntilNodeCount` (Compose 1.4+). Google's post [Alternatives to idling resources in Compose tests](https://developer.android.com/blog/posts/alternatives-to-idling-resources-in-compose-tests-the-wait-until-ap-is-updated) covers the pattern.
- For animations and timed UI, take control of the clock: `composeTestRule.mainClock.autoAdvance = false`, then `advanceTimeBy(…)`.
- Inject a test dispatcher into the ViewModel so data loads finish under test control.
- Find by `testTag` or semantics, never localized text.

## Espresso

- Register an `IdlingResource` (or `CountingIdlingResource`) for background work Espresso can't see: custom executors, coroutines on non-main dispatchers, image loaders. Espresso already waits for the main looper and `AsyncTask`.
- Never `Thread.sleep` or `SystemClock.sleep`.

## Devices and isolation

- **Android Test Orchestrator** runs each test in its own instrumentation process, so a crash or leftover static state can't spill into the next test. Combine it with `clearPackageData` to wipe app data between tests.

```kotlin
android {
    defaultConfig {
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        testInstrumentationRunnerArguments["clearPackageData"] = "true"
    }
    testOptions {
        execution = "ANDROIDX_TEST_ORCHESTRATOR"
        animationsDisabled = true
    }
}
dependencies {
    androidTestUtil(libs.androidx.test.orchestrator)
}
```

- **Gradle Managed Devices** give every developer and CI the same emulator image, created and torn down by Gradle (`./gradlew pixel8api35DebugAndroidTest`). Prefer an `aosp-atd` system image for headless speed.
- Grant runtime permissions with `GrantPermissionRule`, and disable animations (`animationsDisabled = true`) so transitions don't race assertions.
- Hilt: `@UninstallModules` + `@BindValue` fakes, so tests never hit real singletons shared across tests.

## Retry and quarantine tools

- **Gradle test-retry plugin** (`org.gradle.test-retry`, [repo](https://github.com/gradle/test-retry-gradle-plugin)) retries failed JVM `Test` tasks and reports tests that passed on retry as flaky. It applies to JVM unit tests, not `connectedAndroidTest`.

```kotlin
plugins { id("org.gradle.test-retry") version "<pinned>" }
tasks.withType<Test>().configureEach {
    retry {
        maxRetries.set(2)
        maxFailures.set(10)            // a mass failure is a real break, don't retry it
        failOnPassedAfterRetry.set(false)
    }
}
```

- **`@FlakyTest`** (`androidx.test.filters.FlakyTest`) marks quarantined instrumented tests. Exclude them from the blocking run with `-Pandroid.testInstrumentationRunnerArguments.notAnnotation=androidx.test.filters.FlakyTest` and run them in a separate non-blocking job. Each one carries a `bugId` and an owner.
- **Firebase Test Lab** retries instrumented tests with `gcloud firebase test android run --num-flaky-test-attempts=2` and marks passed-on-retry results as flaky.
- **Marathon** ([marathonlabs/marathon](https://github.com/MarathonLabs/marathon)) is a test runner for Android and iOS with configurable retry, flakiness, and sharding strategies driven by past results.
