# Porting a feature to the other platform

The source platform is the **reference for behavior**. The target platform's rules decide **code shape**.

## 1. Get or write the spec

Look for `docs/features/<feature>.md`. If there isn't one, write it from the reference implementation before porting. It doubles as the review checklist.

```markdown
# Feature: Task list

## Behavior
- Shows the user's tasks, newest first; completed tasks hidden unless the "Show completed" filter is on.
- Pull to refresh; works offline from the local store.

## States
| State | Trigger | UI |
|---|---|---|
| Loading | first load, no cache | progress indicator |
| Empty | no tasks | empty state + "New task" action |
| Content | ≥1 task | list |
| Error | refresh failed, no cache | error + Retry |
| Stale | refresh failed, cache present | list + non-blocking "Couldn't refresh" message |

## Strings
`task_list.title`, `task_list.empty_title`, `task_list.empty_action`, `task_list.refresh_failed`, `task_list.completed_count` (plural)

## Icons
`AppIcon.add` / `AppIcons.Add`, `AppIcon.filter` / `AppIcons.Filter`

## Analytics
`task_list_viewed`, `task_completed { source: list|detail }`

## Deep links
`/tasks` → task list; `/tasks/{id}` → task detail

## Accessibility
Row reads "<title>, <due date>, completed|not completed"; Complete is a custom action.

## Acceptance checks
- Completing a task updates the list immediately and survives a refresh failure.
- Rotating / resizing keeps the filter and scroll position.

## Platform differences (intentional)
- iOS: swipe action to complete; Android: checkbox + swipe.
```

## 2. Read the reference for behavior

Collect, from the reference code: every state and transition, every user action and its effect, error handling and retries, string keys used, icons used, analytics events and their properties, deep links handled, accessibility labels and actions, flags checked. Note anything the spec missed and add it.

Don't carry over: class hierarchy, file structure that only exists because of the source framework, workarounds for source-platform bugs, and framework-specific names.

## 3. Build the target skeleton with the same names

- Module: `FeatureTasks` (SPM) ↔ `:feature:tasks` (Gradle).
- Types: `TaskListViewModel`, `TasksRepository`, `Task`, `TaskListScreen` / `TaskListView`.
- State: Android `TaskListUiState` sealed interface; Apple observable properties or a `TaskListState` enum, per `apple-swiftui-mvvm.md`.
- If the repository or domain model doesn't exist on the target, port it first, following the target's repository rule. With KMP, it already exists in `shared/`.

## 4. Port states and events, then presentation

1. View model with every state from the spec and an event function or method per user action.
2. Unit tests for the view model against a fake repository, one test per state transition in the spec (Swift Testing / Turbine).
3. The stateless screen: render each state, using the target's design-system components, icon vocabulary, and string facade.
4. Platform-native presentation: navigation, sheets, swipe actions, haptics, and toolbar placement per HIG / Material.

## 5. Wire the shared contracts

- Strings: add the keys to the target's catalog/resources with the mapped names (`.` → `_` on Android). Copy the source text and translator comments; never invent new wording silently.
- Icons: add missing entries to `AppIcon` / `AppIcons` under the same meaning name.
- Analytics: use the generated event API; same event names and properties.
- Flags and deep links: same keys and routes; register the route with the target's navigation.

## 6. Verify

Run the target platform's build, lint, and tests from its `CLAUDE.md`. Typical:

```bash
# Apple
xcodebuild -scheme <App> -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build test
swift test --package-path apple/<App>Packages

# Android
./gradlew :feature:tasks:testDebugUnitTest ktlintCheck detekt lintDebug assembleDebug
```

Walk the spec's acceptance checks on a simulator/emulator if one is available, and say which ones you couldn't run.

## 7. Record parity

Update `docs/parity.md` (status and any intentional differences) in the same change.

## Parallel work: two agents, one spec

Once a spec is settled, both platforms can be built at the same time:

```bash
git worktree add ../myapp-apple   -b feature/task-list-apple
git worktree add ../myapp-android -b feature/task-list-android
```

- Run one Claude session (or one platform subagent — see `repo-setup.md`) per worktree, each pointed at the same spec.
- Each session owns only its platform directory; a needed change to `shared/` goes to one owner and the other rebases onto it.
- Review the two diffs side by side against the spec's state table before merging either.
