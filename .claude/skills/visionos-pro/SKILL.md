---
name: visionos-pro
description: Builds and reviews visionOS apps — window, volume, and ImmersiveSpace choice, opening and dismissing spaces, immersion styles, spatial gestures and hover effects, comfort and accessibility on a head-mounted display, RealityKit entity and component patterns, the Reality Composer Pro and USDZ pipeline, and 90 fps performance budgets. Use when adding visionOS support, building an immersive experience, or reviewing spatial code for comfort and performance.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
---

Make spatial apps comfortable, accessible, and smooth: the right scene type, an exit from every immersive state, input that works with eyes and hands, and a steady 90 fps. This is the deep companion to the always-on `apple-visionos-best-practices.md` rule. Report only genuine problems.

Load `references/visionos.md` for the full guidance: scene types, opening and dismissing spaces, immersion styles, spatial gestures and entity input, accessibility on a head-mounted display, RealityKit and ECS patterns, performance budgets, the USDZ pipeline, scene coexistence, and complete code patterns. If doing a partial review, read only the matching section.

## Review Checklist

1. **Scene choice**: a window unless the content needs depth; a volume for one bounded object; an immersive space only for unbounded content, opened by the user.
2. **Immersive lifecycle**: the `openImmersiveSpace` result is checked, a visible exit exists, and the space is dismissed when the scene goes to the background.
3. **Input**: every interactive entity has input-target, collision, and hover-effect components and a large enough target; system gestures and focus are untouched.
4. **Comfort**: Reduce Motion honored for all motion; no head-locked text, continuous camera motion in full immersion, or flashing.
5. **Accessibility**: labels and roles on interactive entities; custom 3D controls respond to VoiceOver.
6. **RealityKit**: content loaded from Reality Composer Pro with failure handled, shallow hierarchies, cached lookups, behavior in components.
7. **Performance**: 90 fps held; triangle, particle, texture, lighting, and shadow budgets respected; unused assets removed.

## Output Format

Group findings by severity: **blocking** (user trapped in immersion, motion that ignores Reduce Motion, head-locked reading content, sustained frame drops), **degraded** (unreachable entities, missing hover feedback, assets over budget), **polish** (hierarchy depth, lookup caching). Give each as file:line, what the wearer experiences, and the fix with before/after. End with the count per severity and the first three fixes.
