---
name: flaky-tests-pro
description: Investigates, fixes, and prevents flaky tests in Apple and Android projects — reproducing a flake on demand (xcodebuild test repetitions, swift test --repeat-until, Gradle and instrumentation loops), classifying the cause (async waits, shared state, order dependence, time, randomness, network, devices), fixing it at the source in Swift Testing, XCTest, XCUITest, JUnit, coroutines, Compose, and Espresso, and setting a CI policy for retries, quarantine, and flake tracking. Use when a test passes and fails without a code change, CI is red intermittently, someone proposes a retry or a skip, or when auditing a suite for flake risk.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
---

A flaky test passes and fails on the same code. It is a bug, either in the test or in the code under test, and a retry only hides it. This skill is the deep companion to the always-on `apple-testing-strategy.md` and `android-testing-strategy.md` rules. Report only genuine problems.

Pick the mode from the request:

- **Fix**: a named test flakes. Reproduce, classify, fix, verify (below).
- **Triage a suite**: CI is intermittently red and nobody knows which tests. Find the flaky set from CI history or repetition runs, rank by failure rate and cost, then fix the top ones.
- **Prevent**: review tests or a PR for flake risk with the checklist below.
- **Set policy**: decide how CI retries, quarantines, and tracks flakes, from `references/ci-policy.md`.

Load only what the task needs:

- `references/causes-and-fixes.md` — the cause taxonomy, the signal each cause leaves, and the fix in Swift and Kotlin. Load for every Fix and Prevent task.
- `references/apple.md` — reproducing with `xcodebuild` repetition flags, test plans, and `swift test`; reading `.xcresult`; Swift Testing, XCTest, and XCUITest fixes; known-issue and disabling APIs.
- `references/android.md` — repeating JVM and instrumented tests, the test-retry plugin, Test Orchestrator, Gradle Managed Devices, Compose and Espresso synchronization, Robolectric loopers, `@FlakyTest`.
- `references/ci-policy.md` — retry and quarantine policy, flake tracking, and the external tools and agent skills worth knowing (Tuist, Develocity, Marathon, Firebase Test Lab, and others).

## Fix Workflow

1. **Reproduce before touching code.** Run the one test many times, in the same conditions CI uses (parallel on, same device or simulator, same order). Record the failure rate, such as 3 of 200. A flake you can't reproduce, you can't prove fixed. If it won't fail alone, run it with its whole suite or with randomized order: the cause is probably shared state or order.
2. **Read the failures, not just the count.** Collect the failure messages and stack traces from several failing runs. Different messages across runs usually mean a race; the same message usually means one bad wait or assumption.
3. **Classify the cause** with `references/causes-and-fixes.md`. Name it in the report ("async wait: asserts before the load finishes").
4. **Fix the source.** Inject the clock, await the real signal, isolate the state, stub the network. Fix the code under test when the race is real there: a flaky test that exposes a production race is the test working.
5. **Verify with the same repetition** that reproduced it, at least 10 times the original failure interval (a 1-in-50 flake needs 500 clean runs). Then run the full suite once to make sure the fix didn't move the problem.
6. **Remove any retry, skip, or known-issue marker** the flake was carrying, in the same change.

Never "fix" a flake by raising a timeout, adding a sleep, adding a retry, or deleting the assertion. Raising a timeout is acceptable only when the operation is genuinely slow and bounded, and the report says so.

## Prevention Checklist

1. **No sleeps.** No `sleep`, `Thread.sleep`, `Task.sleep`, `usleep`, `SystemClock.sleep`, or `delay` used to wait for real work. Await a completion, a confirmation, a predicate, or virtual time.
2. **Controlled time and randomness.** Clocks, `Date()` / `System.currentTimeMillis()`, UUIDs, random seeds, and time zones are injected or fixed.
3. **No shared mutable state between tests.** No statics or singletons left dirty, no `UserDefaults.standard` / real `SharedPreferences`, no fixed file paths, no shared database file. Each test builds its own fixtures.
4. **Order-independent.** Every test passes alone, first, last, and in parallel.
5. **No live network or real services.** Stub at the protocol or transport layer (`URLProtocol`, `MockWebServer`, fakes).
6. **Deterministic assertions.** No reliance on dictionary or set ordering, hash values, floating-point equality without a tolerance, or the device's locale.
7. **UI tests wait on state, never on time,** find elements by identifier or test tag, start from a known app state (launch arguments, cleared data), and run with animations off.
8. **Bounded tests.** A hung test fails fast with a time limit instead of stalling the whole run.
9. **Retries in CI are reported, not silent,** and every quarantined test has an owner and an issue.

## Output Format

For a fix: the test, the reproduction command and failure rate before, the cause category with the evidence, the change (before/after code), and the verification command and clean-run count after.

For a review or triage: group findings by severity: **flaky now** (a reproduced or CI-observed flake), **flake risk** (a checklist violation that will flake under load, parallelism, or another device), **policy** (silent retries, quarantine without owners, no tracking). Give each as file:line, the cause category, and the fix. End with the count per severity and the first three fixes.
