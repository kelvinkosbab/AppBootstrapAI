---
description: Enforce patterns for Apple Foundation Models (on-device LLM) integration — session lifecycle, availability gating, streaming, testability
globs: "**/*.swift"
paths:
  - "**/*.swift"
must:
  - "Session holders are `@MainActor @Observable final class`; keep one `LanguageModelSession` per conversation."
  - "Gate on `SystemLanguageModel.default.availability` (each unavailable reason) and a user preference."
  - "Stream into a placeholder, check `Task.isCancelled` in the loop, and reset `isGenerating` with `defer`."
  - "Only the real implementation imports FoundationModels; inject a protocol so tests use a mock."
---

# Apple Foundation Models

The must-follow rules for on-device and Apple-hosted language models. Code for the session holder, availability utility, streaming loop, mocks, and the Xcode 27 model choices is in [`foundation-models-pro/references/foundation-models.md`](../skills/foundation-models-pro/references/foundation-models.md); read the matching section only when a line below isn't enough. Review with `foundation-models-pro`.

> Beta APIs (`PrivateCloudComputeLanguageModel`, `LanguageModelExecutor`, multimodal input) are named from the Xcode 27 seeds. Verify each against the SDK you build with.

## Sessions

- **The session holder is a `@MainActor @Observable final class`**, never a struct, view, or background actor.
- **One `LanguageModelSession` per conversation**, held as an optional and created lazily. Recreate it only when instructions, tools, or response length change, and say that history is lost.
- Hold it above the navigation boundary that should cancel it, not in a short-lived leaf view.

## Availability

- **Device first**: switch on `SystemLanguageModel.default.availability` and handle each unavailable reason (hide the UI when ineligible, link to Settings when Apple Intelligence is off, wait for the model when it isn't ready yet).
- **Then the user**: a preference so people can turn AI off on capable devices. Expose one observable `isAvailable` for the selected model, and never create a session before checking it.

## Choosing a model

- **On-device by default**; Private Cloud Compute or an external provider (through `LanguageModelExecutor`) per use case, behind `any LanguageModel` in the holder.
- **Data leaving the device needs consent**, the minimum context, and a privacy-manifest update. Gate providers per storefront (`apple-regional-compliance.md`).
- Check a model's capabilities before attaching images, and downsize them first.

## Streaming

- **Append a placeholder message before streaming**, update it in place, and remove it on error.
- **Check `Task.isCancelled` in the loop** and put `defer { isGenerating = false }` at the top.
- Disable send while `isGenerating`. No force-unwraps of the session or stream elements.

## Errors and testing

- **Catch broadly** and show a localized message; log the full error. Don't pattern-match beta error cases.
- **Only the real implementation imports FoundationModels.** Views depend on a protocol (or `any LanguageModel`), injected through `@Environment`, with mock and simulator implementations for tests and previews.
- While streaming, give VoiceOver a localized thinking label and set the final text once, not per token. Profile with the Foundation Models instrument.
