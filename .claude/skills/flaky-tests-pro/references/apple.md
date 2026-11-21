# Flaky Tests on Apple Platforms

Reproduction tools, result reading, and framework-specific fixes for Swift Testing, XCTest, and XCUITest. Check flags against the installed Xcode (`xcodebuild -help`) before encoding them in CI.

## Reproduce

Test repetitions were added in Xcode 13 (WWDC21, "Diagnose unreliable code with test repetitions").

```bash
# Run one test up to 100 times, stopping at the first failure.
xcodebuild test -scheme App -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AppTests/FeedViewModelTests/testRefreshShowsItems \
  -test-iterations 100 -run-tests-until-failure

# Fixed number of iterations, to measure a failure rate.
xcodebuild test … -only-testing:… -test-iterations 200

# Relaunch the test process each iteration, to rule out leftover in-process state.
xcodebuild test … -test-iterations 50 -run-tests-until-failure \
  -test-repetition-relaunch-enabled YES
```

- `-retry-tests-on-failure` (with `-test-iterations N` as the maximum) reruns only failures. It is a CI mitigation, not a reproduction tool; see `ci-policy.md`.
- In Xcode, the test diamond's context menu has **Run "test" Repeatedly…** with the same modes. Test plans hold the same settings under **Test Repetition Mode** (None, Fixed Iterations, Until Failure, Retry on Failure), plus **Execution Order: Random** to expose order dependence.
- Swift packages: `swift test --filter FeedViewModelTests --repeat-until fail --maximum-repetitions 200` (Xcode 27 / Swift 6.4). Never ship `--repeat-until pass` in CI.
- Add `-parallel-testing-enabled YES` and the CI destination to match CI. Many flakes only appear under parallelism or on the slower CI simulator.
- Race suspects: rerun with `-enableThreadSanitizer YES`.

## Read the Results

```bash
xcodebuild test … -resultBundlePath build/Flaky.xcresult
xcrun xcresulttool get test-results tests --path build/Flaky.xcresult      # Xcode 16+
xcrun xcresulttool get test-results summary --path build/Flaky.xcresult
```

The test report in Xcode marks a test that both failed and passed across repetitions as **mixed** results, which is the flake signature. Compare failure messages across iterations: one message means one bad wait, several mean a race.

## Swift Testing

- Tests run **in parallel by default**, including across suites. Shared mutable state (statics, `UserDefaults.standard`, a shared temp path) is the top cause. Use a fresh instance per test (a suite's `init` runs per test) and `.serialized` only on suites that truly share an external resource.
- Await events with `confirmation(expectedCount:)`, which fails if the count isn't met when the closure returns, so the event must happen inside it.
- Bound hangs with `.timeLimit(.minutes(1))` on the test or suite.
- Inject `any Clock<Duration>`; Swift Testing doesn't control time for you.
- Known flake with an owner: `withKnownIssue("Intermittent: #123", isIntermittent: true) { … }` records the failure without failing the test and doesn't fail when the issue doesn't occur. It's quarantine: track it and remove it after the fix.
- Disable with a reason and a link: `@Test(.disabled("Flaky, see #123"), .bug("https://…/123"))`. A disabled test with no linked issue is a deleted test.

## XCTest

- Await async work: `await fulfillment(of: [exp], timeout: 5)` in async tests (not `wait(for:)`, which blocks and can deadlock with the main actor).
- `XCTExpectFailure("Intermittent: #123", options: .nonStrict()) { … }` is XCTest's intermittent quarantine; a strict expectation fails when the issue doesn't happen.
- `setUp` runs per test; reset shared state there. `addTeardownBlock` for cleanup tied to the test.
- `XCTSkip` for environment gaps (no network entitlement, unsupported OS), never for flakes.

## XCUITest

- Wait for state, never time: `element.waitForExistence(timeout:)`, `XCTNSPredicateExpectation` with `isHittable` or a value predicate, then `XCTWaiter().wait(for:timeout:)`. Xcode 15+ adds `waitForNonExistence(timeout:)`.
- Find by `accessibilityIdentifier`, never localized text.
- Start from known state with launch arguments and environment (`-UITestResetState`, stubbed backend URL), so tests don't depend on what the previous test left.
- Disable animations in UI-test builds: check a launch argument in the app and call `UIView.setAnimationsEnabled(false)`, and skip non-essential transitions.
- System alerts: pre-grant permissions with `xcrun simctl privacy <device> grant <service> <bundle-id>` before the run, or handle them with `addUIInterruptionMonitor`. Unexpected alerts are a common CI-only flake.
- `continueAfterFailure = false` so a missing element fails at the cause, not three steps later.
- Clean simulators in CI: a fresh simulator per job or `xcrun simctl erase`, and a pinned runtime.

## Snapshot tests

Pin the simulator model, OS runtime, scale, locale, appearance, and Dynamic Type size; render with a fixed date. Font rendering differs across runtimes, so record and compare on the same image as CI.
