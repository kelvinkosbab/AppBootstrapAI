# CI Policy: Retries, Quarantine, and Tracking

A team needs a written policy, or every red build turns into "just rerun it". Put the decisions below in `CLAUDE.md` or `docs/testing.md` so agents follow them too.

## Retries

- **Retries detect flakes; they don't fix them.** A test that passed on retry is reported as flaky, never as a clean pass.
- **Cap them.** One or two retries per test, and a ceiling on retried failures per run (`maxFailures` in the Gradle plugin). Twenty failures at once is a real break.
- **Retry only where flakes are expensive to block on**: UI and instrumented tests on CI. Unit tests should be deterministic; a retried unit test is a bug to fix this week.
- **Never retry locally by default**, and never in the job that verifies a flake fix.
- Tools: `xcodebuild -retry-tests-on-failure -test-iterations 3` (Xcode 13+); the Gradle `org.gradle.test-retry` plugin for JVM tests; `--num-flaky-test-attempts` on Firebase Test Lab; Marathon retry strategies.

## Quarantine

Quarantine moves a known flaky test out of the blocking run while it gets fixed. It keeps CI trustworthy without deleting the test.

- **Every quarantined test has an issue, an owner, and a date.** Put the issue link in the marker:
  - Swift Testing: `withKnownIssue("…#123", isIntermittent: true)` or `.disabled("…") .bug("…/123")`
  - XCTest: `XCTExpectFailure("…#123", options: .nonStrict())`, or skip it in the CI test plan
  - Android instrumented: `@FlakyTest(bugId = 123)` excluded via `notAnnotation`
  - JVM: a JUnit 5 `@Tag("flaky")` excluded from the blocking task and run in a separate job
- **Quarantined tests still run** in a non-blocking job, so the team sees whether they pass and whether a fix worked.
- **Cap the quarantine** (for example, 10 tests or 2% of the suite) and review it weekly. Past the date, fix or delete with a decision recorded in the issue.
- An agent never quarantines or skips a test on its own to get a green build. It reports the flake and proposes the marker, and a human decides.

## Tracking

- Keep a flake list: test, failure rate, first seen, cause category, owner. CI result history is the source: `.xcresult` bundles and JUnit XML reports are enough to compute "failed then passed on the same commit".
- Rank by failure rate times how many builds it breaks. Fix the top few first; one 5% flake in a 2,000-test suite blocks more merges than ten 0.1% flakes.
- Rerun data is evidence: a test that fails on a commit and passes on the same commit is flaky by definition.

## External tools and agent skills

Options, so a team can choose. None are required; the workflow in `SKILL.md` works with plain `xcodebuild` and Gradle.

| Tool | Platform | What it gives |
|---|---|---|
| [Tuist Test Insights](https://tuist.dev/en/docs/guides/features/test-insights/flaky-tests/xcode) | Apple | Flaky-test detection across CI runs for Xcode projects; Tuist's [`fix-flaky-tests`](https://www.skills.sh/tuist/agent-skills/fix-flaky-tests) agent skill ([tuist/agent-skills](https://github.com/tuist/agent-skills)) reads that data through the `tuist` CLI |
| [Develocity flaky test detection](https://docs.gradle.com/develocity/flaky-test-detection) | Android (Gradle) | Commercial; flags tests that fail and pass on the same inputs, with history and trends |
| [Gradle test-retry plugin](https://github.com/gradle/test-retry-gradle-plugin) | Android (JVM tests) | Open-source retries that report flaky tests |
| [Firebase Test Lab](https://firebase.google.com/docs/test-lab) | Android, iOS | Device farm with flaky-attempt retries |
| [Marathon](https://github.com/MarathonLabs/marathon) | Android, iOS | Test runner with retry, flakiness, and sharding strategies |
| Test analytics services (BuildPulse, Trunk Flaky Tests, Datadog Test Optimization, and others) | Both | Commercial flake detection and quarantine from JUnit XML |

Generic agent skills exist too, for example the `flaky-test-detector` skills on skills.sh and stacklok's `deflake`. They don't cover XCTest, Swift Testing, Compose, or Espresso specifics. Read any third-party skill before adding it: it runs with the agent's permissions (see `ai-steering-files.md`).
