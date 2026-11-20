# Flake Causes and Fixes

Most flaky tests fall into a handful of causes. The categories follow the empirical studies of flaky tests (Luo et al., "An Empirical Analysis of Flaky Tests", FSE 2014, and later work on mobile suites), where async waits, concurrency, and order dependence account for most flakes. Name the category in every finding.

| Cause | Typical signal | Fix |
|---|---|---|
| Async wait | Fails more on slow CI machines or under load; assertion sees the old value | Await the real completion or a predicate; use virtual time |
| Concurrency / race | Different failure messages across runs; crashes in unrelated places; data-race reports | Fix the race in the code under test; isolate actors and dispatchers |
| Order dependence | Passes alone, fails in the suite, or the other way round; changes with parallelism | Give each test its own state; reset in setup, not teardown |
| Time and dates | Fails near midnight, month end, DST changes, or in another time zone | Inject a clock, calendar, time zone, and locale |
| Randomness | Fails on some seeds; `UUID()` or `shuffled()` in the path | Inject the generator or seed; log the seed on failure |
| Unordered collections | Fails when a `Set` or `Dictionary` iterates differently | Sort before comparing, or compare as sets |
| Floating point | Off by a tiny amount on another architecture | Compare with a tolerance |
| Network and services | Timeouts, 5xx, rate limits; fails only on CI | Stub the transport; no live endpoints in unit or UI tests |
| Resources and I/O | Fails when a file, port, or database is left by another test or run | Unique temp paths per test; clean before use |
| Device and environment | One simulator or emulator image, animations, system dialogs, low memory | Pin images, disable animations, grant permissions up front, use managed devices |
| Test framework misuse | Assertions after the test returned; unawaited expectations; vacuous passes | Await everything the test starts; confirm the assertion ran |

## Async Wait

The most common cause. The test checks before the work finished, and a fast machine hides it.

- **Swift**: make the API `async` and `await` it. For callbacks or `AsyncSequence` events, use Swift Testing's `confirmation(expectedCount:)` or XCTest's `fulfillment(of:timeout:)`. Never `Task.sleep` to "let it finish". `Task.yield()` in a loop is a sleep in disguise.
- **Kotlin**: `runTest` with the code under test on the injected `TestDispatcher`, then `advanceUntilIdle()` or `runCurrent()`. Turbine `awaitItem()` for flows. In UI tests, `composeTestRule.waitUntil { … }` or the `waitUntilExactlyOneExists` family, or an Espresso `IdlingResource`.
- A timeout on a real wait is a ceiling for failure, not a delay: set it generously (seconds), because a short one turns slow machines into flakes.

## Concurrency and Races

- Run the test with the data-race tooling on: Thread Sanitizer (`-enableThreadSanitizer YES`) on Apple, Swift 6 strict concurrency at compile time, and on Android a `StandardTestDispatcher` that makes ordering explicit.
- If the race is in production code, fix it there and keep the test. The flake was a correct bug report.
- Don't serialize a whole suite (`.serialized`, `--no-parallel`, `maxParallelForks = 1`) to hide a race. Serialize only tests that truly share an external resource, and say which resource.

## Order Dependence

- Find it by running the test alone, then the suite in random order and in parallel. On Apple, test plans can randomize execution order; Swift Testing already runs tests in parallel. On Android, JUnit 5 supports `@TestMethodOrder(MethodOrderer.Random::class)`.
- Typical polluters: singletons and `static`/`object` state, `UserDefaults.standard`, `SharedPreferences`, the Keychain, on-disk caches, an in-memory database shared through DI, `Locale` or `TimeZone` defaults changed by one test, `Dispatchers.setMain` without `resetMain`.
- Reset state at the **start** of each test so one crashed test can't poison the next.

## Time, Randomness, Locale

- Swift: inject `any Clock<Duration>` (a test clock or immediate clock), a `now: () -> Date`, a `Calendar` and `TimeZone`, and a `RandomNumberGenerator`.
- Kotlin: inject `java.time.Clock` or `kotlinx.datetime.Clock`, a `TimeSource`, and `Random(seed)`. Use the `TestScope`'s `testScheduler` / `currentTime` for coroutine time.
- Formatters in assertions use a fixed `Locale` (`en_US_POSIX` on Apple, `Locale.ROOT` or an explicit locale on Android).

## Network, Files, and Devices

- Apple: a `URLProtocol` subclass registered on a test `URLSessionConfiguration`, or a protocol-level fake. Temp files under `FileManager.default.temporaryDirectory` with a UUID folder per test.
- Android: OkHttp `MockWebServer` or fake repositories; JUnit `TemporaryFolder` / `@TempDir`; in-memory Room (`Room.inMemoryDatabaseBuilder`) per test.
- Devices: see the platform references for animations, permissions, and clean app state.

## Framework Misuse (vacuous or late assertions)

- A callback that asserts after the test returned is never checked (vacuously green) or fails a later test (flaky). Await it.
- An unstructured `Task { … }` or `launch { … }` inside a test must be awaited or joined.
- Prove a fixed test can fail: break the code under test once and watch the test go red.
