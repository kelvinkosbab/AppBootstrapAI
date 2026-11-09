---
description: Region-specific App Store rules for Apple apps — storefront availability, China mainland (ICP filing, generative-AI and third-party AI brand mentions, game licenses, CallKit), EU trader status, storefront-based feature gating with StoreKit, neutral per-region metadata, and answering a regional rejection
globs: "**/{*.swift,*.xcstrings,*.strings,Info.plist,*.entitlements,PrivacyInfo.xcprivacy,Fastfile,Deliverfile},**/fastlane/metadata/**"
paths:
  - "**/{*.swift,*.xcstrings,*.strings,Info.plist,*.entitlements,PrivacyInfo.xcprivacy,Fastfile,Deliverfile}"
  - "**/fastlane/metadata/**"
must:
  - "Decide availability per storefront and record it in `docs/compliance/regions.md`."
  - "No third-party AI brand names (ChatGPT, Claude, Gemini, …) in UI or metadata where the provider isn't filed, including China."
  - "Gate features with one injected `RegionPolicy` from `Storefront.countryCode`, failing closed when unknown."
  - "Keep store metadata neutral and in the repo; it's reviewed per storefront."
---

# Apple Regional Compliance

The must-follow rules for shipping to App Store storefronts with different laws. China mainland requirements, the `RegionPolicy` code, the register format, and other regions' rules are in [`store-compliance-pro/references/apple-storefronts.md`](../skills/store-compliance-pro/references/apple-storefronts.md); read the matching section only when a line below isn't enough. Audit a release or answer a rejection with `store-compliance-pro`.

## Availability

- **Choose storefronts deliberately.** "All countries" claims compliance everywhere; remove a storefront where a feature can't legally run.
- **Record each decision** in `docs/compliance/regions.md` so a later release doesn't re-add the region.
- **China mainland** needs an ICP filing number, CAC filing for public generative AI, an NPPA number for games, CallKit/VoIP disabled, and approved maps (GCJ-02). Unlicensed VPN, crypto, and gambling features can't ship there.

## Third-party brands and AI

- **No third-party AI brands** (ChatGPT, Claude, Gemini) in the app name, subtitle, keywords, icon, UI strings, or screenshots where the provider isn't allowed, including China.
- Get explicit consent before sending personal data to a third-party AI (Guideline 5.1.2(i)); the consent screen may name the provider.
- Provider names belong in code identifiers, not user-facing strings.

## Gate by storefront

- **One injected `RegionPolicy`** built from `Storefront.current?.countryCode` (alpha-3, `"CHN"`), re-evaluated on `Storefront.updates`. No scattered country checks.
- **Never gate on `Locale.current`**, time zone, IP, or SIM.
- **Fail closed** for regulated features when the storefront is unknown.
- **Gate every surface**: entry points, settings, onboarding, App Shortcuts, widgets, and notifications. If review still flags the feature, exclude the storefront.

## Metadata and rejections

- **Keep metadata neutral and in the repo** (`fastlane/metadata/`); provider claims only in localizations for storefronts that allow them. Explain region gating in App Review notes.
- **Answer a regional rejection** by reading the guideline and storefront, picking one fix (exclude, gate and neutralize, or obtain the license), searching the binary and every metadata locale, then replying in Resolution Center and updating the register.
