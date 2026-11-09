---
name: foundation-models-pro
description: Writes and reviews Apple Foundation Models code — LanguageModelSession ownership in a MainActor Observable holder, availability gating per unavailable reason, streaming with placeholders and cancellation, Private Cloud Compute and external models through LanguageModelExecutor, multimodal input, error handling, testability with protocol mocks, and VoiceOver for streamed output. Use when adding an on-device AI feature or reviewing one.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
---

Make on-device and Apple-hosted model features reliable: available only where they work, responsive while streaming, cancellable, private by default, and testable without a device. This is the deep companion to the always-on `apple-foundation-models.md` rule. Report only genuine problems.

> Several APIs here (`PrivateCloudComputeLanguageModel`, `LanguageModelExecutor`, `LanguageModelCapabilities`, multimodal input) come from the Xcode 27 seeds. Verify each symbol against the SDK in use before citing it in a finding.

Load `references/foundation-models.md` for the full guidance: session ownership, availability gating with a `switch` over every unavailable reason, choosing between on-device, Private Cloud Compute, and external models, multimodal input, streaming, error handling, the protocol + mock + simulator pattern, SwiftUI integration, accessibility for streamed output, and complete code patterns. If doing a partial review, read only the matching section.

## Review Checklist

1. **Ownership**: the session lives in a `@MainActor @Observable final class`, one per conversation, recreated only when its configuration changes.
2. **Availability**: every `.unavailable` reason handled distinctly, plus a user preference; no session created before the check.
3. **Model choice**: the holder depends on `any LanguageModel`; data that leaves the device has consent, minimum context, a privacy-manifest entry, and per-storefront gating.
4. **Streaming**: placeholder appended first and removed on error; `Task.isCancelled` checked in the loop; `defer { isGenerating = false }`; send disabled while generating.
5. **Errors**: caught broadly, shown localized, logged in full; no matching on beta error cases.
6. **Testability**: only the real implementation imports FoundationModels; mock and simulator implementations exist and are injected.
7. **Accessibility**: a localized thinking label while streaming, the final text set once.

## Output Format

Group findings by severity: **blocking** (no availability check, data sent off-device without consent, generation that can't be cancelled, `isGenerating` stuck after an error), **degraded** (session recreated per prompt, empty bubble left on error, untestable direct imports), **polish** (naming, accessibility labels). Give each as file:line, the user-visible effect, and the fix with before/after. End with the count per severity and the first three fixes.
