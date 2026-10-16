---
description: Region-specific App Store rules for Apple apps — storefront availability, China mainland (ICP filing, generative-AI and third-party AI brand mentions, game licenses, CallKit), EU trader status, storefront-based feature gating with StoreKit, neutral per-region metadata, and answering a regional rejection
globs: "**/{*.swift,*.xcstrings,*.strings,Info.plist,*.entitlements,PrivacyInfo.xcprivacy,Fastfile,Deliverfile},**/fastlane/metadata/**"
---

# Apple Regional Compliance

One binary ships to 175 storefronts, but each storefront has its own law, and App Review enforces it per storefront. A feature or a single word that passes in the US can get the whole submission rejected for another region. The classic case: **KozBon was rejected for the China mainland storefront because the app and its App Store metadata mentioned ChatGPT.** China requires generative-AI services offered to the public to be filed with the regulator, and foreign AI services like ChatGPT are not, so naming one (in the UI, the description, keywords, screenshots, or release notes) is enough to fail review there.

These rules make region a first-class design input: decide per storefront, gate features through one policy type, keep metadata neutral, and keep a register of what each region needs. For a full audit of an app and its listing, invoke the **`store-compliance-pro`** skill. Age-rating and age-assurance gates are in [`apple-testflight-deployment.md`](./apple-testflight-deployment.md); privacy manifests and third-party AI consent are covered there and in [`apple-foundation-models.md`](./apple-foundation-models.md).

> **Law moves faster than this file.** Requirements below are current as of late 2026. Before acting on one, check the cited guideline in the current App Review Guidelines and App Store Connect Help, and treat a rejection message as the authority for that submission.

## Decide Availability Per Storefront — Deliberately

- **Pricing and Availability lists every storefront the app ships to.** "All countries" is a legal claim that you comply everywhere. For each storefront you can't support, remove it rather than hope review misses it.
- **Excluding a storefront is a normal, reversible choice.** If a core feature can't legally run in a region (generative AI from an unfiled foreign provider in China, unlicensed real-money gaming, an unlicensed VPN), dropping that storefront is usually cheaper than a separate product.
- **Record the decision** in `docs/compliance/regions.md` (see below) so the next release, and the next agent, doesn't silently re-add the region.

## China Mainland

The storefront with the most region-only requirements. Each one is a rejection or removal trigger:

- **ICP filing (备案).** Apps distributed in mainland China need an MIIT ICP filing number, entered in App Store Connect (App Information). Without it, the app can't be offered in China. Filing needs a mainland legal entity or partner; if you have neither, exclude the storefront.
- **Generative AI.** Public-facing generative-AI services require filing with the Cyberspace Administration of China (Interim Measures for Generative AI Services, 2023). Apple removed unfiled AI apps from the China store and rejects apps that integrate unfiled services. In practice:
  - **Don't name third-party AI products or companies** (ChatGPT, OpenAI, Claude, Anthropic, Gemini, Grok, and similar) in the UI, onboarding, settings, or any metadata shown on the China storefront.
  - **Don't call unfiled foreign model APIs** for China-storefront users. Hide the feature, or route to a provider that holds a Chinese filing and show its filing number where required.
  - **Apple Intelligence and Foundation Models** availability varies by region. `SystemLanguageModel.default.availability` reports it at runtime; never assume on-device AI exists in China.
- **Games** need an NPPA approval number (版号) entered in App Store Connect before they can ship in China. No number, no storefront.
- **CallKit and VoIP calling** must be disabled for China (MIIT). Gate it through the region policy below.
- **Maps** must show officially approved borders and place names, and mainland coordinates use the GCJ-02 datum. MapKit handles this inside China; custom tiles, bundled geodata, or raw WGS-84 overlays don't.
- **Other restricted categories** include unlicensed VPNs, cryptocurrency exchanges and mining, gambling, and content the regulator treats as politically sensitive (flags, maps, region names). Review any of these before keeping China in availability.

## Other Regional Requirements

| Region | Requirement | Where it lives |
|---|---|---|
| **EU** | Digital Services Act **trader status** declared, or the app is removed from EU storefronts. Trader contact details appear on the product page. | App Store Connect ▸ Business |
| **EU / Japan** | Alternative distribution and payment options (DMA, Japan's Mobile Software Competition Act) change entitlement and commission terms, not baseline review. | Opt-in addenda; only if you adopt them |
| **South Korea, Vietnam, others** | Games need a local rating or license number before release. | App Store Connect game info |
| **Australia, Brazil, Singapore, US states** | Age assurance and social-feature gating. | [`apple-testflight-deployment.md`](./apple-testflight-deployment.md) |
| **Worldwide, varies by law** | Real-money gaming, lending, crypto, medical claims, and VPNs need a license in each jurisdiction where offered (Guidelines 5.3, 5.4, 1.4). | Availability + review notes |

## Third-Party Brands and AI in Every Storefront

These apply everywhere, and they're what turns a China-specific issue into a global one:

- **Don't use another company's trademark** (ChatGPT, Gemini, Claude) in the app name, subtitle, keywords, or icon (Guidelines 2.3.7, 4.1, 5.2). Describe the capability: "AI assistant", "smart summaries".
- **Disclose and get explicit permission before sending personal data to a third-party AI** (Guideline 5.1.2(i)). Name the provider in that consent screen, which is a legitimate place for the brand, and gate the screen by region like the feature.
- **Keep provider names in code identifiers, not user-facing strings.** A `BonjourAIAnthropic` module is fine; a `Text("Ask ChatGPT")` is not. Route the visible label through the localization facade as a generic string.

## Gate by Storefront, Not Locale

Legal jurisdiction follows the **App Store account's storefront**, not the device language or region setting. A user in Shanghai with an English device has a China storefront; a Chinese-speaking user in Vancouver doesn't.

```swift
import StoreKit

/// Features whose availability depends on the user's App Store storefront.
enum RegulatedFeature: Sendable, CaseIterable {
    case externalAIProviders, voipCalling, realMoneyGaming
}

/// The single place that maps storefronts to feature availability.
struct RegionPolicy: Sendable {
    /// ISO 3166-1 alpha-3 storefront code, e.g. "CHN". `nil` when unknown.
    let storefrontCountryCode: String?

    func allows(_ feature: RegulatedFeature) -> Bool {
        // Unknown storefront: fail closed for regulated features.
        guard let code = storefrontCountryCode else { return false }
        switch feature {
        case .externalAIProviders: return code != "CHN"
        case .voipCalling:         return code != "CHN"
        case .realMoneyGaming:     return Self.licensedGamingStorefronts.contains(code)
        }
    }

    private static let licensedGamingStorefronts: Set<String> = []
}

@MainActor @Observable
final class RegionPolicyStore {
    private(set) var policy = RegionPolicy(storefrontCountryCode: nil)

    func observe() async {
        policy = RegionPolicy(storefrontCountryCode: await Storefront.current?.countryCode)
        for await storefront in Storefront.updates {
            policy = RegionPolicy(storefrontCountryCode: storefront.countryCode)
        }
    }
}
```

- **`Storefront.current?.countryCode` is alpha-3** (`"CHN"`, `"USA"`), not the alpha-2 that `Locale.Region` uses. Mixing them silently disables or enables everything.
- **Never gate on `Locale.current`, time zone, IP, or SIM.** They describe the user's preferences or network, not the store whose rules apply.
- **One `RegionPolicy`, injected; no scattered `if code == "CHN"` checks.** Put it in a small module (see [`apple-modular-architecture.md`](./apple-modular-architecture.md)) so features ask `policy.allows(.externalAIProviders)` and the rules are unit-testable with literal codes.
- **Fail closed for regulated features** when the storefront is unknown (offline first launch), and re-evaluate on `Storefront.updates`.
- **Gate the whole surface**: the entry point, settings toggles, onboarding mentions, App Shortcuts, widgets, and notifications. A hidden screen that still appears in Spotlight or a Siri phrase still fails review.
- **Interface/implementation modules make this cheap.** With a `BonjourAICore` interface and one module per backend, the routing umbrella simply omits backends the policy disallows.
- **Runtime gating isn't a substitute for availability.** If App Review still flags the feature, the binary's strings or the reviewer's region test made the case; exclude the storefront.

## Metadata Is Reviewed Per Storefront

App Review reads every field shown on a storefront, and **a storefront without its own localization shows your primary language**. Neutral English text is therefore the China listing unless you add a Simplified Chinese one.

- **Name, subtitle, keywords, description, promotional text, What's New, screenshots, and app previews** all count. A screenshot of a "Powered by ChatGPT" badge fails exactly like the description does.
- **Write metadata neutral by default**, and put provider-specific claims only in localizations for storefronts where they're allowed.
- **Keep metadata in the repo** (`fastlane/metadata/<locale>/`, `deliver`) so it's reviewed in PRs and scanned by the audit like code.
- **Use App Review notes** to state region gating: "AI chat is disabled on the China mainland storefront via StoreKit storefront check; see `RegionPolicy`." Reviewers test with regional accounts; tell them what they'll see.

## Answering a Regional Rejection

1. **Read the cited guideline and the storefront** in the Resolution Center message. Region rejections usually cite Guideline 5 (Legal) or 5.1.x and name the storefront.
2. **Pick one fix**: exclude the storefront, gate the feature and neutralize metadata, or obtain the license or filing. Don't argue that the feature is "only a link".
3. **Search the binary and the listing**, not just the obvious screen: string catalogs, `Info.plist` purpose strings, onboarding, help text, screenshots, and every metadata locale (the `store-compliance-pro` audit has the search).
4. **Reply in the Resolution Center** with what changed and where, then resubmit. Record the outcome in `docs/compliance/regions.md`.

## Keep a Compliance Register

`docs/compliance/regions.md` is the source of truth agents read before touching availability, AI providers, or metadata:

```markdown
| Storefront | Status | Requirements | Implemented in | Last verified |
|---|---|---|---|---|
| China mainland | Excluded | ICP filing; generative-AI filing (none for our providers) | Pricing & Availability | 2026-10 (rejection: ChatGPT mentions) |
| EU | Available | DSA trader status | App Store Connect ▸ Business | 2026-10 |
| All | Available | 5.1.2(i) AI consent | `AIConsentView`, `RegionPolicy` | 2026-10 |
```

- Update it in the same change that adds a storefront, an AI provider, a payment method, or a regulated feature.
- Add it to the release checklist next to the privacy report and age rating.

## Common Pitfalls

- **Third-party AI brand names in UI strings or metadata.** The single most common regional rejection for AI apps, and a trademark risk everywhere.
- **"All countries" availability by default** with features that are illegal or unlicensed in some of them.
- **Gating on `Locale.current`** instead of the storefront.
- **Comparing `Storefront.countryCode` to alpha-2 codes.**
- **Scattered country checks** instead of one tested `RegionPolicy`.
- **Hiding the screen but not its shortcuts, widgets, notifications, or onboarding copy.**
- **Neutralizing one localization** while the primary language, shown on every unlocalized storefront, still names the provider.
- **Calling foreign AI APIs for China users** after hiding only the UI.
- **No register**, so a fixed region silently regresses on the next release.
