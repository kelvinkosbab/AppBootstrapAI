---
description: Motion design for Jetpack Compose apps — purpose before properties, motion tokens in :core:designsystem (M3 MotionScheme springs, easing and duration tokens), spatial vs. effects specs, entrance vs. exit timing, no linear spatial motion, draw-phase animation, one hero per moment, reduced-motion alternatives for every spatial or looping animation, predictive back, haptics, and Lottie playback rules
globs: "**/*.{kt,kts}"
paths:
  - "**/*.{kt,kts}"
must:
  - "Animate from motion tokens in :core:designsystem (MotionScheme or named specs), never ad hoc durations or easings."
  - "Every spatial, scaling, or looping animation has a reduced alternative when system animations are off."
  - "Never use LinearEasing for movement; linear is only for spinners, progress, and timers."
  - "Motion never carries information alone and never blocks input while it plays."
---

# Android Motion Design

Motion is part of the interface, not decoration. A good animation answers one question (where did this come from, did my tap work, what changed) and gets out of the way; a bad one makes the app feel slow, hides state, or makes people feel sick. Material 3 components, Navigation, and the system back gesture already animate correctly: don't re-animate them. This rule covers the custom moments. The cross-platform `motion-design-pro` skill designs a motion system, specs interactions with designers, and reviews existing animation.

> **Sources.** Motion principles, timing tables, and patterns adapted from the LottieFiles [motion design skill](https://github.com/lottiefiles/motion-design-skill) (MIT, © 2025 LottieFiles), rewritten for Jetpack Compose and combined with the Material 3 motion guidelines and the Compose animation documentation.

## Decide Before You Animate

- **Name the purpose first**: feedback (the tap worked), orientation (where content came from or went), state change (what changed), attention (look here, rarely), or delight (a reward, rarer still). No purpose, no animation.
- **Pick the primary property from the purpose**: position for arriving and leaving, scale for press and emphasis, alpha combined with one of those for appearing, color for state, rotation only for progress or a playful accent. One property is direct, two is polished, three is usually too many.
- **The app has one motion personality** (see `motion-design-pro` → `principles.md`), chosen once in `AppTheme`: M3 standard motion for most apps, M3 Expressive for brands that want more spring. Borrow a livelier spec only for a specific moment such as success.
- **The same interaction animates the same way every time.**

## Motion Tokens

- **Tokens live in `:core:designsystem`** next to the theme (see [`android-design-system.md`](./android-design-system.md)). With Material 3 1.4+, read springs from `MaterialTheme.motionScheme` (check whether your version still needs an `@OptIn` for it); otherwise define named specs once:

```kotlin
object AppMotion {
    // M3 easing tokens
    val Standard = CubicBezierEasing(0.2f, 0f, 0f, 1f)
    val EmphasizedDecelerate = CubicBezierEasing(0.05f, 0.7f, 0.1f, 1f) // entering
    val EmphasizedAccelerate = CubicBezierEasing(0.3f, 0f, 0.8f, 0.15f) // leaving

    fun <T> feedback() = spring<T>(dampingRatio = 0.9f, stiffness = Spring.StiffnessMedium)
    fun <T> enter() = tween<T>(durationMillis = 300, easing = EmphasizedDecelerate)
    fun <T> exit() = tween<T>(durationMillis = 200, easing = EmphasizedAccelerate)
    fun <T> celebrate() = spring<T>(dampingRatio = Spring.DampingRatioMediumBouncy)
}
```

- **Spatial vs. effects**: position, size, scale, and rotation use spatial specs (`motionScheme.defaultSpatialSpec()`, may overshoot); color and alpha use effects specs (`defaultEffectsSpec()`, never overshoot). A bouncing alpha flickers.
- **Prefer springs**: they keep velocity when interrupted. Use `tween` with M3 easing for exits and fixed-length sequences.
- **Bounce budget**: damping ratio 1 for errors, destructive actions, and premium brands; about 0.8–0.9 for feedback; `DampingRatioMediumBouncy` only for celebrations.
- **Timing by element** (M3 duration tokens, phone baseline): press/toggle 100–150 ms, icon change 150–250 ms, card or row 200–300 ms, custom dialog or sheet 250–350 ms, screen-level transition 300–450 ms. Larger travel takes a little longer (tablet and desktop windows ≈1.1–1.25×); Wear OS is shorter and simpler; TV is slower and focus-driven.
- **Exits are faster than entrances** (about 65–75% of the entrance duration): decelerate into place on entry, accelerate on exit.

## Writing Animations

- **Use the highest-level API that fits**: `animate*AsState` for one value, `updateTransition` for several values driven by one state, `AnimatedVisibility` and `AnimatedContent` for appearing and swapping, `animateContentSize()` for size changes, `Animatable` for gesture-driven motion, `rememberInfiniteTransition` for loops.
- **Animate in the draw phase**: read animated values inside `Modifier.graphicsLayer { alpha = …; translationY = … }` or `Modifier.offset { IntOffset(…) }` so a frame doesn't recompose. Animating `padding`, `size`, or `height` relayouts every frame; fine for one container, a jank source in lazy lists.
- **Enter and exit combine movement with alpha**: `fadeIn() + slideInVertically { it / 4 }`, and in `AnimatedContent` `(fadeIn() + slideIn…) togetherWith fadeOut()`. Give items in `LazyColumn` `Modifier.animateItem()` for inserts, removals, and moves.
- **Continuity**: shared elements with `SharedTransitionLayout` and `Modifier.sharedElement` (check whether your Compose version still needs `@OptIn(ExperimentalSharedTransitionApi::class)`).
- **Predictive back**: never fight the system back animation. Custom back-driven motion follows the gesture's progress via `PredictiveBackHandler`, and the app keeps `android:enableOnBackInvokedCallback="true"`.
- **One hero per moment**: with several elements, stagger them (30–60 ms apart, total under ~500 ms) in reading order, from the trigger's side. Don't move more than about a third of the screen's elements at once.
- **Never block input** while an animation plays; let a new gesture interrupt it.
- **Pair feedback with haptics where the system would**: `LocalHapticFeedback.current.performHapticFeedback(HapticFeedbackType.Confirm)` (or `Reject`, `LongPress`), or `View.performHapticFeedback(HapticFeedbackConstants.CONFIRM)` on older Compose. Haptics never replace a visible state change.

## Reduced Motion and Comfort

- **"Remove animations" sets the animator duration scale to 0.** Compose scales its own animations by it, so tweens and springs jump to their end, but nothing picks a reduced alternative for you. Check it once and expose it from the design system:

```kotlin
@Composable
fun rememberReducedMotion(): Boolean {
    val resolver = LocalContext.current.contentResolver
    return remember(resolver) {
        Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}

val reduced = rememberReducedMotion()
AnimatedVisibility(
    visible = shown,
    enter = if (reduced) fadeIn() else fadeIn() + slideInVertically { it / 4 },
    exit = if (reduced) fadeOut() else fadeOut() + slideOutVertically { it / 4 },
)
```

- **Loops stop when motion is reduced**: pulses, shimmer, floating, and auto-playing Lottie show a still frame you chose, not whatever frame the scale-0 loop stopped on. Any animation longer than about 5 seconds needs a way to pause it.
- **Motion never carries information alone**: an error shake comes with error text and an icon; a success pop comes with a checkmark and text. TalkBack users see none of it, so expose the state through semantics too (see [`android-accessibility-best-practices.md`](./android-accessibility-best-practices.md)).
- **Avoid vestibular triggers**: large zooms, full-screen slides that aren't navigation, spinning large elements, multi-layer parallax, fast direction changes.

## Lottie and Designer-Made Animations

- **Load Lottie through `lottie-compose`** (`rememberLottieComposition` + `LottieAnimation` or `animateLottieCompositionAsState`); prefer `.lottie` (dotLottie) files for size. Wrap it in a design-system component so playback, theming, and reduced motion are handled once.
- **Play once for feedback** (`iterations = 1`), loop (`LottieConstants.IterateForever`) only for loading or ambient states, and show a still frame (the final frame for success) when motion is reduced. Recent Lottie Android versions can follow the system setting through their reduced-motion option; confirm the version you pin does.
- **Decorative animations are cleared from semantics** (`Modifier.clearAndSetSemantics {}`); meaningful ones get `Modifier.semantics { contentDescription = … }` stating the result ("Payment complete").
- **Theme colors in code** with `rememberLottieDynamicProperties` on named layers, so dark theme and brand changes don't need a new export.
