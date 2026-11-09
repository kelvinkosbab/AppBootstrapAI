---
description: Region-specific distribution rules for Android apps — Play country availability and per-country policy declarations, China's non-Play stores (ICP filing, consent-before-collection, GMS-free builds, generative-AI filing and third-party AI brand mentions), EU trader status, developer verification, Play-country feature gating, neutral per-country listings, and answering a regional rejection
globs: "**/{*.kt,*.kts,AndroidManifest.xml,strings.xml,Fastfile,Appfile},**/fastlane/metadata/**"
paths:
  - "**/{*.kt,*.kts,AndroidManifest.xml,strings.xml,Fastfile,Appfile}"
  - "**/fastlane/metadata/**"
must:
  - "Decide availability per country and record it in `docs/compliance/regions.md`."
  - "No third-party AI brand names (ChatGPT, Gemini, …) in UI or listings where the provider isn't filed, including China."
  - "Gate features with one injected `RegionPolicy` from the store country (`BillingConfig.countryCode`), failing closed when unknown."
  - "China builds ship outside Play: GMS-free flavor and consent before any data collection."
---

# Android Regional Compliance

The must-follow rules for shipping to countries with different laws. China store requirements, the `RegionPolicy` code, other regions' rules, and the search commands are in [`store-compliance-pro/references/android-countries.md`](../skills/store-compliance-pro/references/android-countries.md); read the matching section only when a line below isn't enough. Audit a release or answer a rejection with `store-compliance-pro`.

## Availability

- **Choose Play countries deliberately.** Remove countries where a feature needs a license you lack; gambling, loans, and similar policies are country-specific.
- **Record each decision** in `docs/compliance/regions.md` so a later release doesn't re-add the country.
- **Developer verification** applies to sideloaded and alternative-store builds too.

## China: not Google Play

- Ship through Chinese stores with an **ICP filing**, store verification, and often a software copyright certificate.
- **A GMS-free `china` flavor**: no Play Services, Firebase, Play Billing, or Google sign-in, including transitively.
- **Consent before any data collection**: no device identifiers, installed-app lists, clipboard, location, or third-party SDK initialization before consent.
- Generative AI needs a CAC filing; games need an NPPA number; maps use approved borders and GCJ-02.

## Third-party brands and AI

- **No third-party AI brands** (ChatGPT, Gemini, Claude) in titles, descriptions, icons, screenshots, or `strings.xml` where the provider isn't allowed. Provider names belong in module and class names.
- Generative-AI apps let users report offensive output in-app, and disclose AI data sharing in the Data safety form.

## Gate by store country

- **One `RegionPolicy`, injected through Hilt** and exposed as `StateFlow`, from `BillingConfig.countryCode` (alpha-2, `"CN"`). Shared tables in a two-platform repo say whether codes are alpha-2 or alpha-3.
- **Never gate on `Locale.getDefault()`, SIM country, or IP.** Fail closed when the country is unknown.
- Prefer build-time exclusion (a flavor, or conditional delivery with `<dist:user-countries>`) when a whole market differs. Gate every surface, including shortcuts, notifications, and deep links.

## Listings and rejections

- **Keep listings neutral and in the repo** (`fastlane/metadata/android/` or Triple-T `src/main/play/`); use custom store listings for country-specific claims.
- **Answer a regional rejection** by reading the policy and country, picking one fix, searching code, resources, and every listing, then resubmitting or appealing and updating the register.
