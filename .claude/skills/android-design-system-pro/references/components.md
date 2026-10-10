# Components audit

The goal is fewer, better components: each pattern implemented once on top of Material 3, adapting and accessible everywhere.

## Wrap, don't reimplement

| Need | Use | Avoid |
|---|---|---|
| Branded button | thin wrapper over `Button` / `FilledTonalButton` / `OutlinedButton` / `TextButton` | `Box(Modifier.clickable { })` with a background |
| Icon action | `IconButton` / `FilledIconButton` / `IconToggleButton` | clickable `Icon` |
| Card | `Card` / `ElevatedCard` / `OutlinedCard` (clickable overload when tappable) | `Column(Modifier.background().clickable())` |
| List row | `ListItem` (headline/supporting/leading/trailing slots) | bespoke `Row` per screen |
| Text input | `OutlinedTextField` / `TextField` with `supportingText` + `isError` | custom `BasicTextField` chrome for ordinary forms |
| Top bar | `TopAppBar` family + `scrollBehavior` | custom `Row` headers |
| Navigation | `NavigationSuiteScaffold` (adapts by size class) | a `NavigationBar` everywhere |
| Dialog / sheet | `AlertDialog` / `ModalBottomSheet` | custom overlays |
| Chips | `FilterChip` / `AssistChip` / `InputChip` | toggled pill `Box`es |

- A reimplemented control loses ripple/indication, focus and keyboard activation, `Role` semantics, disabled semantics, and the 48dp minimum target. That's a **broken-tier** finding, not a style nit.
- `BasicTextField` is right for genuinely custom inputs (OTP boxes, inline editors) — then it must supply its own semantics and focus handling.

## The core component set

Roughly what a new app needs — scaffold these and stop:

- Buttons: primary, secondary (tonal/outlined), text, icon.
- Top app bar wrapper with the app's defaults; navigation suite wrapper.
- Card (slot-based), list item wrapper with leading-icon conventions.
- Text field with error/supporting text conventions.
- Feedback: loading, empty, and error states (with retry action) as one family; snackbar host conventions.
- Dialog wrapper with the app's button order and text styles.

Add components when a pattern appears a **third** time; flag speculative components nothing uses.

## API shape (Compose component guidelines)

- Required parameters first; **`modifier: Modifier = Modifier` is the first optional parameter**; then optional parameters; then the trailing `@Composable` content lambda.
- `modifier` applied to the **root** element only, exactly once. Flag `modifier` passed to an inner child or ignored.
- **Slots** (`content: @Composable RowScope.() -> Unit`, `leadingContent: (@Composable () -> Unit)?`) instead of configuration flags.
- **`XxxDefaults` objects** for tunable defaults (`colors()`, `ContentPadding`, `shape`), matching M3's `ButtonDefaults` style.
- **Text as `String` from the caller** (already resolved via `stringResource`) or a slot — the component never contains English literals.
- No ViewModel, repository, `NavController`, or `:data` model parameters — events go out through lambdas.

## Stability and state

- Stateless with hoisted state (`value` / `onValueChange`); internal `remember` only for visual state (interaction sources, animation).
- Parameters stable: primitives, `@Immutable` data classes, `ImmutableList` for collections, method references or remembered lambdas at call sites. Deep dives go to `android-compose-pro`.
- No side effects in components (analytics, haptics policy, network) — expose callbacks.

## Accessibility baked in

- Compound rows merge (`Modifier.semantics(mergeDescendants = true)` or `ListItem`, which merges).
- Section headers carry `semantics { heading() }`.
- Custom toggles/selection use `toggleable` / `selectable` with `Role`.
- Long-press/swipe affordances mirrored as `customActions`.
- Animations inside components respect reduce-motion.

## Previews, catalog, screenshot tests

- Each public component: previews wrapped in `AppTheme` using `@PreviewLightDark`, `@PreviewFontScale`, `@PreviewDynamicColors` (and `@PreviewScreenSizes` for layout-level components), covering default, disabled, loading/error, and long-text states. Preview functions are `private` or `internal` and live next to the component.
- A **catalog** (an `:app-catalog` module or a debug screen) shows every component — the Now in Android pattern. Flag its absence once the design system has more than a handful of components.
- **Screenshot tests** for the design system — Compose Preview Screenshot Testing (AGP plugin, experimental), Roborazzi (Robolectric, JVM), or Paparazzi (layoutlib, JVM). Pick one; run light/dark × 1.0/2.0 font scale; keep reference images reviewed in PRs. Components are where screenshot tests pay off most.
- Previews and catalog excluded from coverage (see `android-testing-strategy.md`).

## Duplicate inventory

- Search for composables named `*Button`, `*Card`, `*Header`, `*EmptyState`, and for `clickable` on `Box`/`Row`/`Column`/`Text`. Group by role; more than one per role is an inconsistency finding with a convergence recommendation (keep the M3-backed, accessible one).

## Audit sequence

1. Inventory component-like composables and duplicates per role.
2. Check each for wrap-vs-reimplement and accessibility.
3. Check API shape (modifier position/usage, slots, ViewModel parameters, literals).
4. Check previews/catalog/screenshot-test coverage.
5. Propose convergence order: broken implementations first, then most-used duplicates.
