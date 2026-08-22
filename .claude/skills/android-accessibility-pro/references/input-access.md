# Bluetooth assistive input — keyboards, Switch Access, braille

Three input methods, one semantics tree. The audit question per screen: can it be *operated* (not just read) without the touchscreen?

## External keyboards (Bluetooth) and D-pad

Pair a keyboard (or use the emulator's D-pad): Tab/arrows move focus, Enter/Space activate.

- **Reachability**: `Modifier.clickable` / `toggleable` / real Material components are focusable automatically. Findings hide in:
  - Bare `Modifier.pointerInput { detectTapGestures(...) }` — never focusable, never keyboard-activatable. Fix: use `clickable`, or add `focusable()` + `semantics { onClick(label) { ...; true } }`.
  - Custom drag/swipe-only interactions with no focusable equivalent.
  - Overlay content stacked above focusables — focus lands on obscured elements.
- **Activatability**: focus without a working Enter/Space action is still a failure — the semantics `onClick` must actually invoke the behavior.
- **Focus visibility**: never remove the focus indicator. Custom `Indication` keeps ≥ 3:1 contrast; `LocalIndication` overrides that null it out are findings.
- **Order**: default traversal follows layout; fix genuine breaks with `focusProperties { next/previous }` or `focusGroup()` — and flag focus order that differs wildly from the TalkBack traversal order (they should agree).
- **Traps**: search fields consuming Tab, infinite pagers, bottom sheets without an escape — verify a keyboard path out of every container.

## Switch Access (Bluetooth switches)

Scanning steps through focusable/actionable nodes and activates on switch press. It consumes the same tree as keyboard focus + TalkBack actions:

- **Scan stops = tree nodes**: fragmented rows multiply stops (the merge findings from `semantics.md` pay off here); inert-but-focusable decorations waste every cycle.
- **Gesture mirrors are mandatory**: swipe/long-press affordances must exist as `CustomAccessibilityAction`s — Switch Access presents them in its menu; without the mirror the feature simply doesn't exist for switch users.
- **Group sensibly**: `isTraversalGroup` / row-level clickables turn a card into one stop with actions, instead of five stops.
- Point-scan fallback exists but is miserable — treat "works only via point scan" as unreachable.

## Braille displays (TalkBack + Bluetooth HID)

OS-level HID braille since Android 15 / TalkBack 15; TalkBack renders your semantics onto a 14–40 cell line. There is no separate braille API — **`contentDescription` and `stateDescription` are the braille output**.

- **Front-load meaning**: the distinguishing words first; the tail falls off the display.
- **Short, plain text**: emoji, decorative punctuation, and repeated boilerplate render as literal braille noise — flag labels containing them.
- **Distinct prefixes in lists**: rows sharing a long common prefix force panning on every row — lead with what differs.
- **Textual state beats implied state**: `stateDescription` text renders on the display; state conveyed only through announcement timing or visual change does not.

## Audit sequence

1. Trace every interactive Composable to its focusability: `clickable`/`toggleable` (fine) vs `pointerInput`-only (finding).
2. Walk each screen's node order; list order breaks, fragmented rows, inert stops.
3. Cross-check every swipe/long-press/drag against the `CustomAccessibilityAction` list.
4. Grep `contentDescription`/`stateDescription`/action-label strings for emoji, length outliers, shared prefixes, and hardcoded English.
5. Where the project has instrumented tests, suggest a keyboard-navigation test (`performKeyPress`/focus assertions) for the worst screen found.
