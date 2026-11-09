---
description: Patterns for visionOS apps — scene types, immersion styles, spatial gestures, RealityKit / ECS conventions, head-mounted-display accessibility, USDZ pipeline, performance budgets
globs: "**/*.swift"
paths:
  - "**/*.swift"
must:
  - "Check the `openImmersiveSpace` result, provide a visible exit, and dismiss when the scene backgrounds."
  - "Honor Reduce Motion for all motion; world-lock readable content, never head-lock text."
  - "Every interactive entity needs a hover effect plus input-target and collision components."
  - "Hold 90 fps; frame drops cause nausea."
---

# visionOS Best Practices

The must-follow rules for visionOS apps. Scene and immersion code, gesture examples, RealityKit and asset-pipeline detail, and the performance numbers are in [`visionos-pro/references/visionos.md`](../skills/visionos-pro/references/visionos.md); read the matching section only when a line below isn't enough. Review with `visionos-pro`.

## Scenes and immersion

- **Start with a `WindowGroup`**; use a volumetric window for one bounded 3D object, and an `ImmersiveSpace` only when the content needs unbounded space. Only one immersive space can be open system-wide.
- **Check the `openImmersiveSpace` result** (the user can cancel), **always provide a visible exit**, and dismiss the space when `scenePhase` goes to the background.
- **Open immersion from a deliberate user action**, never at launch. Prefer `.mixed`, use `.progressive` for optional focus, and `.full` only when the environment is the point.

## Input and comfort

- Use spatial gestures (`SpatialTapGesture`, `RotateGesture3D`) targeted to entities. Don't replace system gestures or the gaze focus indicator.
- **Every interactive entity has `InputTargetComponent`, `CollisionComponent`, and `HoverEffectComponent`**, with targets no smaller than about 30 pt at 1 m (eye tracking is accurate to about half a degree).
- **Honor Reduce Motion for all motion**, not only decoration. No continuous camera movement in full immersion, no flashes or strobing.
- **World-lock readable content**; never head-lock text.

## Accessibility

- Every interactive entity has an accessibility label and role; custom 3D controls set `accessibilityRespondsToUserInteraction`.
- Trapping the user in an immersive state is an accessibility failure.

## RealityKit

- Author scenes, materials, and particles in Reality Composer Pro and load them with async-throwing `Entity(named:in:)`, handling failure.
- Keep entity hierarchies shallow, cache `findEntity` lookups, and drive per-frame behavior with components and systems.
- Ship `.usdz`, source-control `.usda`, and drop unused assets.

## Performance

- **Hold 90 fps** (11.1 ms per frame); frame drops cause discomfort.
- Stay within the budgets: about 100k triangles per entity, under 1,000 live particles, 2048² textures, baked shadows, image-based lighting over real-time lights.
