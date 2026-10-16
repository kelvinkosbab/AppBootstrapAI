# Responding to a Regional Rejection

## 1. Classify it

Pull three facts from the Resolution Center message (Apple) or the policy email / Policy status page (Play), or the Chinese store's review report:

- **Region**: the storefront or country named. Apple names it in the message ("…in China mainland"); Chinese Android stores name the store.
- **Rule**: the guideline or policy cited (Apple Guideline 5 Legal, 5.1.x privacy, 2.3.7 metadata, 4.1 copycats; Play Metadata, Impersonation, AI-Generated Content, financial or gambling policies).
- **Trigger**: what the reviewer saw. A feature, a word in the UI, a metadata field, a screenshot, an SDK behavior, or a missing filing number.

KozBon's case classifies as: China mainland · legal (generative-AI rules) · "ChatGPT" in the app and in metadata.

## 2. Choose the fix

| Option | When | Cost |
|---|---|---|
| **Exclude the region** | The feature is core to the app and illegal or unfiled there; or the region isn't worth a separate path | Lowest. Reversible in the console. |
| **Ship without the feature there** | The app is valuable without it | Apple: `RegionPolicy` gating + neutral strings + neutral metadata. Android: a market flavor or runtime gating. Medium. |
| **Make the feature compliant** | The region matters and a compliant route exists | Highest. A locally filed provider, an ICP filing, a game license, a gambling license. Weeks to months. |
| **Neutralize wording only** | The feature is allowed and only the brand mention is the problem (trademark, or a provider that is allowed) | Low. Generic labels; provider named only on a consent screen. |

Recommend one with the reason. For a foreign AI provider in China, wording alone is not enough: the feature itself needs gating or the storefront excluded.

## 3. Sweep

Run `references/audit.md` sections 2 and 3 for the whole app, not just the screen in the rejection. Reviewers cite the first instance they find; resubmitting with the next instance still in place costs another round. Sweep:

- String catalogs and resources, including accessibility labels and `Info.plist` purpose strings.
- Onboarding, settings, help, empty states, error messages, and push notification copy.
- App Shortcuts phrases, widgets, Spotlight, deep links.
- Every metadata locale, the primary locale, screenshots, previews, and in-app event cards.
- Server-driven content the app displays (remote config, CMS copy, changelogs).

## 4. Reply and review notes

Resolution Center reply (Apple), adapt to what changed:

```text
Thank you for the review. We have [removed China mainland from the app's availability /
disabled the AI chat feature on the China mainland storefront]. The app now checks the
App Store storefront (StoreKit Storefront.countryCode) and does not show the feature, its
settings, or its shortcuts on that storefront. We also removed references to third-party AI
services from the app's interface and from the App Store metadata in all localizations.
We have submitted build [version (build)] for review.
```

App Review notes for the next submissions, so the reviewer knows what to expect:

```text
Region gating: AI chat uses third-party model providers and is disabled on the China mainland
storefront (StoreKit storefront check in RegionPolicy). Reviewers using a China mainland
account will not see the AI tab or its settings.
```

Play: use the Policy status page to resubmit or appeal with the same facts. Chinese stores: resubmit through the store console; their reports name the exact API or string, so reply with the commit that removed it.

Only state what is true. Never describe gating that doesn't exist, and never target review accounts differently from real users.

## 5. Register and policy seam

If the project has no register, create `docs/compliance/regions.md`:

```markdown
# Regional compliance register

Storefront codes: Apple uses ISO 3166-1 alpha-3 (CHN), Play uses alpha-2 (CN).

| Region | Apple | Android | Requirements | Implemented in | Last verified |
|---|---|---|---|---|---|
| China mainland | Excluded | Not distributed | ICP filing; CAC filing for generative AI (none for our providers) | Pricing & Availability | 2026-10 (rejected over ChatGPT mentions) |
| EU | Available | Available | DSA trader status | App Store Connect ▸ Business; Play account | 2026-10 |
| All | Available | Available | Third-party AI consent (Apple 5.1.2(i)); AI content reporting (Play) | `AIConsentView`, `ReportAIOutput` | 2026-10 |

## Rejection log

| Date | Store | Region | Rule | Trigger | Fix |
|---|---|---|---|---|---|
| 2026-10 | App Store | China mainland | Legal (generative AI) | "ChatGPT" in UI and metadata | Excluded storefront; neutral strings |
```

If regulated features are checked ad hoc, add the `RegionPolicy` seam from the platform rule (`apple-regional-compliance.md`, `android-regional-compliance.md`) in a small module, with unit tests that pass literal codes:

```swift
@Test(arguments: ["CHN"]) func blocksExternalAI(storefront: String) {
    #expect(!RegionPolicy(storefrontCountryCode: storefront).allows(.externalAIProviders))
}

@Test func unknownStorefrontFailsClosed() {
    #expect(!RegionPolicy(storefrontCountryCode: nil).allows(.externalAIProviders))
}
```

```kotlin
@Test fun `external AI is blocked in China`() {
    assertFalse(RegionPolicy(storeCountryCode = "CN").allows(RegulatedFeature.ExternalAiProviders))
}
```

Add the register to the release checklist, and update it in the same change as any availability, provider, or regulated-feature change.
