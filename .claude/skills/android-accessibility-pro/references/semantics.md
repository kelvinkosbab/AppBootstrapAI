# The TalkBack semantics tree

TalkBack (and every other Android assistive tech) consumes the semantics tree Compose derives from your modifiers. Audit what the tree exposes node by node — a screen that looks fine can be unusable if nodes are fragmented, unlabeled, or stale.

## Descriptions, roles, state

- **Meaningful images/icons** set `contentDescription` via `stringResource(...)`; **decorative** ones pass `null` (not `""`). When an icon sits beside text carrying the same meaning, the icon is decorative — double-described rows are a finding.
- **Roles for custom controls**: anything mimicking a button/checkbox/switch/tab declares it — `Modifier.semantics { role = Role.Button }` (or via `clickable(role = ...)` / `toggleable(role = ...)`, which is preferred because it also wires the action). A styled `Box` with `pointerInput` and no role is invisible as a control.
- **`stateDescription` for changing values** — toggle state, progress, selection. Two audit points: it exists, AND it updates with state (a string captured once at composition is a stale-state bug). `contentDescription` describes *what it is*; `stateDescription` describes *what it currently says*.
- **Text fields**: label association (`Modifier.semantics { contentDescription }` on the field or a proper `label = {}`), error state via `semantics { error("...") }` — not color-only.
- **Disabled controls** still appear in the tree with disabled state (Compose handles it for `enabled = false`); custom disabling via alpha + ignoring clicks hides the state — flag it.

## Structure — merging and traversal

- **Compound rows merge**: `Modifier.semantics(mergeDescendants = true) { }` on the row container (or `clickable` on the row, which merges implicitly). Fragmented rows multiply swipes for TalkBack and scan stops for Switch Access.
- **Headings gate navigation**: section titles get `Modifier.semantics { heading() }` — TalkBack users navigate by heading first. Zero headings on a long screen = linear-swipe purgatory.
- **Traversal order**: follows composition layout order; audit `Box` overlays and floating action buttons where visual order diverges. `Modifier.semantics { traversalIndex = ... }` + `isTraversalGroup = true` fix order deliberately — flag ad-hoc uses without need.
- **Pane titles for navigation-level changes**: each screen/pane sets `Modifier.semantics { paneTitle = ... }` so screen changes are announced consistently.
- **Dialogs/overlays**: Compose `Dialog`/`ModalBottomSheet` contain focus correctly; custom full-screen overlays drawn in a `Box` do not — check that background content is excluded (`invisibleToUser()` on the obscured layer, judiciously).

## Custom actions

- **Every gesture-only affordance needs a `CustomAccessibilityAction` mirror**: swipe-to-dismiss, long-press menus, drag-to-reorder. TalkBack surfaces them in the actions menu; Switch Access and braille users reach them the same way.
- Action labels: localized, verb-first, short. The label list is also the braille output — no emoji.
- `SwipeToDismissBox` and friends don't emit actions automatically — the mirror is on you; verify it exists wherever a swipe modifier appears.

## Announcements — the migration audit

- **`View.announceForAccessibility()` and `TYPE_ANNOUNCEMENT` are deprecated (Android 16)** and behave inconsistently across TalkBack/braille. Every occurrence is a finding with a semantic replacement:
  - In-place critical updates (errors, results arriving) → `Modifier.semantics { liveRegion = LiveRegionMode.Polite }` (`.Assertive` only for must-interrupt errors).
  - Screen/pane changes → `paneTitle`.
  - Control state → `stateDescription`.
- **Live-region scope**: the modifier goes on the message container (snackbar text, error banner), never a whole screen — it fires on every recomposed text change within it.
- **Don't double-speak**: state already carried by a focused node's `stateDescription` doesn't also need a live region.
- Streamed text (AI chat): never announce per chunk — a "generating" `stateDescription` while streaming, final content when done (see `android-ai-best-practices.md`).

## View-interop notes

For remaining `View` code: `contentDescription`, `importantForAccessibility`, `accessibilityLiveRegion`, `ViewCompat.setAccessibilityDelegate` for roles/actions, `setAccessibilityPaneTitle`. In `AndroidView`-wrapped composables, the inner View's semantics carry through — audit them there, not on the wrapper.

## Verification

Semantics are testable: `composeTestRule.onNodeWithContentDescription(...)`, `assert(hasStateDescription(...))`, `onNode(hasAnyAncestor(isDialog()))`. Point findings at a semantics test where one would lock the fix in — these double as the a11y regression suite (see `android-testing-strategy.md`).
