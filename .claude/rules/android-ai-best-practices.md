---
description: Enforce patterns for on-device and cloud AI models in Android apps — Gemini Nano / ML Kit GenAI, Firebase AI Logic, streaming into Compose, availability gating, key safety, testability
globs: "**/*.{kt,kts}"
---

# Android AI Best Practices

Rules for app code that calls generative models — the Android counterpart to [`apple-foundation-models.md`](./apple-foundation-models.md). The Android surface splits into **on-device** (Gemini Nano via ML Kit GenAI APIs / AICore) and **cloud** (Gemini via Firebase AI Logic, or your own backend). Both are network-call-shaped: they can be unavailable, slow to warm up, and they stream. Treat them like I/O, never like a synchronous function.

> **Fast-moving surface.** The GenAI APIs ship in waves (ML Kit GenAI feature set, AICore device list, Firebase AI Logic SDK names). Verify exact artifact/class names against the current SDK release notes before hardcoding — the *patterns* below are stable; the symbols move.

## Choosing a Model: On-Device vs Cloud

- **ML Kit GenAI APIs (Gemini Nano, on-device)** — high-level task APIs (summarization, proofreading, rewriting, image description) running on-device via AICore. Free, private, offline-capable — but **device-limited** (recent flagships) and task-constrained. Default here for cheap/private/offline turns.
- **Firebase AI Logic (cloud Gemini)** — full Gemini capability from app code without running your own backend. Needs network, costs per token, and data leaves the device. Use for harder reasoning, long context, or devices Nano doesn't cover.
- **Your own backend proxy** — when you need server-side prompt assembly, RAG, or multi-provider routing. The app talks to *your* API; the model key never ships in the APK.
- **Pick per use-case, not globally.** Wrap model access behind one interface so a turn can route on-device first and fall back to cloud (or vice versa) without touching call sites.

## API Keys — the Non-Negotiable

- **Never ship a raw model API key in the APK.** Embedded keys are extracted within hours of release (strings in DEX, `BuildConfig`, or `local.properties` leaking through CI). This is the single most common mistake in AI-generated Android code.
- **Use Firebase AI Logic with App Check** (Play Integrity attestation) so requests are authorized per-app-instance without a bundled secret, or route through your own backend.
- The `Never hardcode API keys or secrets` rule in [`android-project-rules.md`](./android-project-rules.md) applies doubly here — a leaked Gemini key bills *you*.

## Availability Gating (Two Levels)

- **Device/feature eligibility first.** On-device GenAI features must be *checked and possibly downloaded* before first use — never assume the model is present. Gate UI on a feature-status check and trigger the download with progress UX; handle "device not eligible" by hiding the AI affordance entirely (don't show a button that can never work).
- **Then user-level gating** — a preference (DataStore-backed) so users can disable AI features even on capable devices, and a consent gate before any cloud call (see Privacy below).
- **Surface availability as state** (`StateFlow<AiAvailability>` from a repository), not via ad-hoc checks sprinkled through Composables.

## Architecture & Streaming

- **Generation state lives in a ViewModel** (`@HiltViewModel`), exposed as `StateFlow<UiState>` — never in `remember { }` (rotation kills it mid-generation). Standard rules from [`android-coroutines-best-practices.md`](./android-coroutines-best-practices.md) apply: `viewModelScope`, injected dispatchers, read-only flow exposure.
- **Stream, don't block.** Use the streaming variant (`generateContentStream`-style, exposed as a cold `Flow`) and collect in `viewModelScope`. A 15-second blocking single-shot reads as a hang.
- **Placeholder-then-mutate** (mirrors the Apple FM rule): append an empty assistant message *before* collecting, mutate it in place as chunks arrive, remove it on error so the transcript never shows an empty bubble.
- **Cancellation is structural.** `viewModelScope` cancels collection when the screen dies; don't catch `CancellationException`. Offer a visible stop button that cancels the collecting `Job`.
- **`defer`-equivalent:** clear `isGenerating` in a `finally` block, not after the happy path — the send button must re-enable on error and cancellation too.

## Error Handling

- **Catch broadly at the generation boundary** and surface a friendly, localized message. Cloud calls fail for quota, safety-filter blocks, network, and region reasons — pattern-matching exact exception subtypes across SDK releases is churn; log the real exception, show a summary.
- **Safety blocks are not crashes.** A response blocked by safety settings is an expected outcome — render a "couldn't help with that" state, don't retry-loop it.
- **Budget for the cloud path**: cap context you send (token cost), debounce rapid-fire sends, and back off on quota errors.

## Privacy & Data Safety

- **Cloud calls send user content off-device — get consent first** and send only what the task needs. On-device inference is the privacy-preserving default; say so in UX when it matters.
- **Never log prompts or completions** at INFO+ — they're user content (see [`android-logging-strategy.md`](./android-logging-strategy.md)). Correlate with request IDs instead.
- **Declare it in the Play Data safety form.** Adding a cloud AI SDK changes your data-collection answers (see [`android-play-beta-deployment.md`](./android-play-beta-deployment.md)); a mismatch between the form and observed traffic is a removal risk.

## Testability — Interface + Fake

- **Define an interface** (`GenerativeBackend`, `SummarizerClient`) owned by your code; production views/ViewModels depend on it, never on SDK types directly. Bind the real implementation in a Hilt module.
- **Ship a fake** that streams canned chunks on a test dispatcher — deterministic unit tests (Turbine over the emission sequence) and `@Preview`/demo builds that work on any device or emulator (which may lack AICore entirely).
- **Test the unhappy paths**: unavailable-feature state, mid-stream error (placeholder removed), cancellation (no dangling `isGenerating`).

## Accessibility for Streamed Output

The streamed-AI rules from [`android-accessibility-best-practices.md`](./android-accessibility-best-practices.md) apply: a localized "thinking" `stateDescription` while generating; don't announce every chunk (TalkBack stutters); decorative typing indicators get no semantics; respect reduce-motion for shimmer effects.

## Patterns to Follow

```kotlin
// Interface owned by your code — SDK types stay in the impl module.
interface GenerativeBackend {
    val availability: StateFlow<AiAvailability>
    fun generate(prompt: String): Flow<String>          // cold; emits text chunks
}

// ViewModel — placeholder-then-mutate streaming with structural cancellation.
@HiltViewModel
class ChatViewModel @Inject constructor(
    private val backend: GenerativeBackend,
) : ViewModel() {

    private val _state = MutableStateFlow(ChatUiState())
    val state: StateFlow<ChatUiState> = _state.asStateFlow()

    private var generation: Job? = null

    fun send(prompt: String) {
        generation?.cancel()
        generation = viewModelScope.launch {
            val placeholderId = appendAssistantPlaceholder()
            _state.update { it.copy(isGenerating = true) }
            try {
                backend.generate(prompt).collect { chunk ->
                    appendToMessage(placeholderId, chunk)   // mutate in place
                }
            } catch (e: Exception) {                        // CancellationException rethrows past this
                removeMessage(placeholderId)
                _state.update { it.copy(error = e.toUserMessage()) }
            } finally {
                _state.update { it.copy(isGenerating = false) }
            }
        }
    }

    fun stop() { generation?.cancel() }
}
```

## Common Pitfalls

- **A Gemini API key in `BuildConfig` / `local.properties`** — shipped secrets get extracted. Firebase AI Logic + App Check, or a backend proxy.
- **Assuming Gemini Nano exists** — it's a download on a limited device list. Check, download with UX, hide the feature when ineligible.
- **Generation state in `remember { }`** — dies on rotation mid-stream. ViewModel + `StateFlow`.
- **Blocking single-shot calls** — stream and render incrementally.
- **Catching `CancellationException`** in the generation collect — breaks structured cancellation (same rule as everywhere else).
- **Logging prompts/completions** — user content in Logcat and crash breadcrumbs.
- **Skipping the Data safety update** when adding a cloud AI SDK — Play removal risk.
- **Mocking the SDK's final classes directly** — wrap in your own interface; fake that.
