# Verify on SDK

Some rules and skills cite APIs that were still **beta** when they were written: the Foundation Models pluggable-model and image-input APIs, Siri tools in 27.3, and the macOS 27.3 direct-touch opt-outs. Beta symbols get renamed or dropped between seeds, and each file only says "verify against the SDK". This list is where that check is tracked.

## When to run it

At each Xcode release: every beta seed, every release candidate, and the GM of a point release that carries one of the APIs below (27.3 especially).

1. Install the new Xcode and note its build (for example `27.3 beta 2 (27C5021e)`).
2. For each row, confirm the symbol in the SDK. Grepping the interface is enough:
   ```bash
   SDK=$(xcrun --sdk iphoneos --show-sdk-path)   # macosx for the Mac-only rows
   grep -rl 'PrivateCloudComputeLanguageModel' "$SDK/System/Library/Frameworks/FoundationModels.framework"
   ```
   For a build setting or entitlement, check Xcode's build-settings reference or create a scratch target.
3. If it still matches, put the seed in **Last verified**. If it was renamed, moved, or left beta, fix every file in the row in the same PR, update the row, and note it in the CHANGELOG.
4. When an API ships in a GM and its spelling matches, drop the "Beta" wording from the cited files and move the row to **Graduated**.

**Last verified** is `—` until someone has checked the row against a real SDK. The names come from Apple's DocC and the Xcode 27 agent skills, not from a compiled check.

## Foundation Models (Xcode 27, beta)

| Symbol | Cited in | Status when written | Last verified |
|---|---|---|---|
| `LanguageModel` (protocol a session runs against) | `.claude/rules/apple-foundation-models.md`, `.claude/skills/foundation-models-pro/references/foundation-models.md` | Beta | — |
| `PrivateCloudComputeLanguageModel` | `.claude/rules/apple-foundation-models.md`, `.claude/skills/foundation-models-pro/references/foundation-models.md` | Beta | — |
| `LanguageModelExecutor` | `.claude/rules/apple-foundation-models.md`, `.claude/skills/foundation-models-pro/references/foundation-models.md` | Beta | — |
| `LanguageModelExecutorGenerationRequest` | `.claude/skills/foundation-models-pro/references/foundation-models.md` | Beta | — |
| `LanguageModelExecutorGenerationChannel` | `.claude/skills/foundation-models-pro/references/foundation-models.md` | Beta | — |
| `LanguageModelCapabilities` | `.claude/skills/foundation-models-pro/references/foundation-models.md` | Beta | — |
| `Prompt` with `Attachment`, `AttachmentContent`, `ImageAttachmentContent` | `.claude/skills/foundation-models-pro/references/foundation-models.md` | Beta | — |
| `ImageReference` in `Transcript` | `.claude/skills/foundation-models-pro/references/foundation-models.md` | Beta | — |
| `LanguageModelError` cases (`unavailable`, `exceededContextWindowSize`) | `.claude/skills/foundation-models-pro/references/foundation-models.md` | Beta; the reference says not to match cases | — |
| Foundation Models Instrument | `.claude/rules/apple-foundation-models.md`, `.claude/skills/foundation-models-pro/references/foundation-models.md` | New in Xcode 27 | — |

## App Intents and Siri (27.3, beta)

| Symbol | Cited in | Status when written | Last verified |
|---|---|---|---|
| `@AppIntent(.tool)`, `ToolIntent` | `.claude/rules/apple-app-intents.md`, `.claude/skills/app-intents-pro/references/siri-integration.md` | 27.3 | — |
| `@AppIntent(schema:)`, `@AppEntity(schema:)`, `@AppEnum(schema:)` replacing the `@Assistant*` macros | `.claude/rules/apple-app-intents.md` | 27.3 | — |
| `@AppEntity(.generable)` | `.claude/skills/app-intents-pro/references/siri-integration.md` | 27.3 | — |
| Property `description:` and `visibility: .internal` | `.claude/rules/apple-app-intents.md`, `.claude/skills/app-intents-pro/references/siri-integration.md` | 27.3 | — |
| `Skills.skillsbundle` (app skills for Siri) | `.claude/skills/app-intents-pro/references/siri-integration.md` | 27.3 | — |
| `xcrun sirimetadataanalyzer` | `.claude/rules/apple-app-intents.md`, `.claude/skills/app-intents-pro/references/siri-integration.md` | 27.3 | — |
| `SiriEvaluations`: `SiriScenarioLoader`, `SiriService.run(scenario:)`, `.evaluates(…)` trait | `.claude/skills/app-intents-pro/references/testing-and-evaluation.md` | 27.3 | — |
| `AppIntentsTesting` | `.claude/skills/app-intents-pro/references/testing-and-evaluation.md` | 27.0 | — |
| `LongRunningIntent`, `performBackgroundTask(options:operation:)`, `allowedExecutionTargets` | `.claude/skills/app-intents-pro/references/ios26-27-apis.md` | 27.0 | — |
| `IndexedEntityQuery`, `relatedAppEntityIdentifier` | `.claude/skills/app-intents-pro/references/ios26-27-apis.md` | 27.0 | — |
| `RelevantEntities`, `SyncableEntity`, `OwnershipProvidingEntity`, `EntityCollection`, `AppUnionValue`, `SystemShortcut` | `.claude/skills/app-intents-pro/references/ios26-27-apis.md` | 27.0 | — |

## Mac touch (macOS 27.3, beta)

| Symbol | Cited in | Status when written | Last verified |
|---|---|---|---|
| `.directTouchSystemGesturesDisabled()` | `.claude/rules/apple-mac-touch.md`, `.claude/skills/swiftui-pro/references/mac-touch.md`, `.claude/skills/swiftui-pro/references/mac-touch-conventions.md` | 27.3 beta | — |
| `NSWindow.disablesDirectTouchSystemGestures` | `.claude/skills/swiftui-pro/references/mac-touch-conventions.md` | 27.3 beta | — |
| `GestureInputKinds` and the `inputKinds:` overloads | `.claude/skills/swiftui-pro/references/mac-touch-conventions.md` | 27.0 | — |
| `NSScrollView.isTouchScrollingEnabled`, `minimumNumberOfTouchesForScrolling` / `maximumNumberOfTouchesForScrolling` | `.claude/skills/swiftui-pro/references/mac-touch-conventions.md` | 27.0 | — |

## Build security (Xcode 27)

| Symbol | Cited in | Status when written | Last verified |
|---|---|---|---|
| `ENABLE_ENHANCED_SECURITY`, `ENABLE_POINTER_AUTHENTICATION` | `.claude/rules/apple-build-security.md`, `.claude/skills/xcode-security-pro/` | Xcode 27 settings | — |
| Entitlements `com.apple.security.hardened-process` and `…enhanced-security-version-string = "2"` | `.claude/rules/apple-build-security.md` | Xcode 27 | — |
| `-ld_classic` removed | `.claude/rules/apple-testflight-deployment.md`, `.claude/skills/beta-deployment-pro/references/testflight.md`, `.claude/rules/apple-spm-package-conventions.md` | Xcode 27 | — |

## Adaptive layout and iPhone Duo (iOS 27.1)

| Symbol | Cited in | Status when written | Last verified |
|---|---|---|---|
| `ArrangementView`, reserved-region (fold / camera) APIs | `.claude/rules/apple-adaptive-layout.md`, `.claude/skills/swiftui-pro/references/resizability.md` | 27.1 | — |
| `toolbarVerticalEdge`, `toolbarVerticalBehavior`, `toolbarVerticalCompressionBehavior`, `axisBehavior` | `.claude/skills/swiftui-pro/references/resizability.md` | 27.1 | — |
| Zero default `UIView` layout margins on 27.1+ (Xcode 27.2) | `.claude/rules/apple-adaptive-layout.md` | Xcode 27.2 | — |

## Graduated

APIs confirmed in a GM SDK with the spelling the files use. Keep the row so a later rename can be traced.

| Symbol | Confirmed in | Files updated |
|---|---|---|
