---
description: Region-specific distribution rules for Android apps — Play country availability and per-country policy declarations, China's non-Play stores (ICP filing, consent-before-collection, GMS-free builds, generative-AI filing and third-party AI brand mentions), EU trader status, developer verification, Play-country feature gating, neutral per-country listings, and answering a regional rejection
globs: "**/{*.kt,*.kts,AndroidManifest.xml,strings.xml,Fastfile,Appfile},**/fastlane/metadata/**"
---

# Android Regional Compliance

One app, many jurisdictions, and each store enforces its own region's law. A provider name in a string, an SDK that reads the Android ID too early, or a loan feature without a local license can block a release in one country while every other country passes. The Apple-side trigger that prompted this rule: **KozBon was rejected for China because the app and its store metadata mentioned ChatGPT**, a generative-AI service with no Chinese filing. The same content fails Chinese Android stores, and the same discipline (decide per region, gate through one policy, keep listings neutral) applies on Play.

For a full audit of an app and its listings, invoke the **`store-compliance-pro`** skill. The Apple counterpart is [`apple-regional-compliance.md`](./apple-regional-compliance.md). The Data safety form is covered in [`android-play-beta-deployment.md`](./android-play-beta-deployment.md); AI consent and key handling in [`android-ai-best-practices.md`](./android-ai-best-practices.md).

> **Policy moves faster than this file.** Requirements below are current as of late 2026. Before acting on one, check the current Play Developer Policy Center and Play Console Help, and treat a rejection or policy email as the authority for that release.

## Decide Availability Per Country — Deliberately

- **Play Console ▸ Production ▸ Countries/regions lists every country you ship to.** Adding "all countries" claims compliance in all of them. Remove countries where a feature needs a license you don't hold.
- **Several Play policies are country-specific**: real-money gambling (licensed countries only, with an application), personal loans (local requirements, e.g. India's RBI-registered lender rules, plus extra rules in Indonesia, Kenya, Nigeria, Pakistan, the Philippines, and Thailand), government and health apps, and news apps. The App content declarations ask per country; answer them for every country you ship to.
- **Record the decision** in `docs/compliance/regions.md` (format in the Apple rule) so a later release doesn't silently re-add the country.

## China: Not Google Play

Google Play and Google Mobile Services don't operate in mainland China. Distribution goes through domestic stores (Huawei AppGallery, Xiaomi, OPPO, vivo, Honor, Tencent MyApp), each with its own review and the same national rules:

- **ICP filing (备案)** with MIIT, plus the store's own developer verification, a mainland entity or publisher, and often a software copyright certificate (软著).
- **Generative AI** needs a CAC filing. **Don't name third-party AI products or companies** (ChatGPT, OpenAI, Claude, Anthropic, Gemini, Grok, and similar) in the UI or the listing, and don't call unfiled foreign model APIs. Firebase AI Logic, Gemini Nano via AICore, and other Google services aren't available there anyway.
- **Consent before collection.** Chinese stores run automated privacy checks (PIPL and MIIT app rules): no reading the Android ID, IMEI, MAC, installed-app list, clipboard, or location, and no third-party SDK initialization, **before** the user accepts the privacy policy on first launch. Defer SDK init behind consent, not in `Application.onCreate()`.
- **A GMS-free build.** Ship a `china` product flavor without Play Services, Firebase, Play Billing, or Google sign-in, using the store's push and payment SDKs. Mixing them in crashes or fails review.
- **Games** need an NPPA approval number (版号). **Maps** must use approved borders and GCJ-02 coordinates. **VPN, crypto, and gambling** features aren't licensable for most foreign developers.

```kotlin
// build.gradle.kts — region is a flavor dimension, not a runtime if-statement
android {
    flavorDimensions += "market"
    productFlavors {
        create("global") { dimension = "market" }
        create("china") {
            dimension = "market"
            applicationIdSuffix = ".cn"
            buildConfigField("boolean", "EXTERNAL_AI_ALLOWED", "false")
        }
    }
}
dependencies {
    "globalImplementation"(libs.firebase.ai)          // never on the china classpath
    "globalImplementation"(libs.play.billing)
}
```

## Other Regional Requirements

| Region | Requirement | Where it lives |
|---|---|---|
| **EU** | Digital Services Act **trader status** declared and verified, or the app is removed from EU distribution. | Play Console ▸ Account details |
| **Brazil, Indonesia, Singapore, Thailand (Sept 2026), then worldwide** | **Android developer verification**: certified devices block installs of apps from unverified developers, including sideloaded and third-party-store builds. | Android Developer Console / Play Console |
| **South Korea, India, EEA, others** | Alternative or user-choice billing programs change payment terms per country. | Play Console ▸ Monetization |
| **Australia, Brazil, Singapore, US states** | Age assurance and age signals for social features. | Play Age Signals API, content rating questionnaire |
| **Worldwide, varies by law** | Real-money gaming, loans, crypto, medical claims, and VPNs need a license wherever offered. | Countries/regions + App content declarations |

## Third-Party Brands and AI on Play

- **Don't use another company's trademark** (ChatGPT, Gemini, Claude) in the title, short description, icon, or screenshots without permission. Play's Metadata and Impersonation policies apply worldwide. Describe the capability instead: "AI assistant", "smart summaries".
- **Generative-AI apps must let users report or flag offensive AI output in-app** and must prevent restricted content (Play AI-Generated Content policy).
- **Disclose AI data sharing** in the Data safety form and get consent before sending user content to a cloud model.
- **Provider names belong in module and class names, not user-facing strings.** `:core:ai:anthropic` is fine; `stringResource(R.string.ask_chatgpt)` is not.

## Gate by Store Country, Not Locale

Policy follows the **user's store country** (the Play account country, or the store a `china` build was installed from), not the device locale, SIM, or IP.

```kotlin
/** Features whose availability depends on the user's store country. */
enum class RegulatedFeature { ExternalAiProviders, RealMoneyGaming }

/** The single place that maps store countries to feature availability. */
data class RegionPolicy(
    /** ISO 3166-1 alpha-2 country, e.g. "CN". Null when unknown. */
    val storeCountryCode: String?,
) {
    fun allows(feature: RegulatedFeature): Boolean {
        if (!BuildConfig.EXTERNAL_AI_ALLOWED && feature == RegulatedFeature.ExternalAiProviders) return false
        val code = storeCountryCode ?: return false   // unknown: fail closed
        return when (feature) {
            RegulatedFeature.ExternalAiProviders -> code != "CN"
            RegulatedFeature.RealMoneyGaming -> code in LICENSED_GAMING_COUNTRIES
        }
    }

    private companion object {
        val LICENSED_GAMING_COUNTRIES = emptySet<String>()
    }
}

// Play country from Play Billing (global flavor), exposed by a repository as StateFlow<RegionPolicy>.
suspend fun BillingClient.storeCountryCode(): String? = suspendCancellableCoroutine { cont ->
    getBillingConfigAsync(GetBillingConfigParams.newBuilder().build()) { result, config ->
        cont.resume(if (result.responseCode == BillingResponseCode.OK) config?.countryCode else null)
    }
}
```

- **`BillingConfig.countryCode` is alpha-2** (`"CN"`, `"US"`), unlike Apple's alpha-3 storefront codes. Shared region tables in a two-platform repo must say which they use.
- **Never gate on `Locale.getDefault()`, `TelephonyManager.simCountryIso`, or IP.** They describe the user's settings or network, not the store whose policy applies.
- **One `RegionPolicy`, injected through Hilt** from a `:core:region` (or `:core:data`) module, exposed as `StateFlow`; features never compare country codes themselves.
- **Fail closed** for regulated features when the country is unknown, and re-query on app start.
- **Build-time beats runtime when a whole market differs.** A `china` flavor removes the code and dependencies; runtime gating within one build still ships the strings and SDKs.
- **Play Feature Delivery can exclude countries at install** with conditional delivery (`<dist:user-countries>` in a dynamic feature module's manifest) when a feature's code shouldn't reach a country at all.
- **Gate every surface**: entry points, settings, onboarding copy, App Shortcuts, widgets, notifications, and deep links.

## Listings Are Reviewed Per Country

- **Title, short and full description, screenshots, feature graphic, video, and release notes** are all reviewed. A "Powered by ChatGPT" screenshot fails like the description does.
- **Write the default listing neutral.** Play's **custom store listings** can target specific countries; put provider-specific claims only in listings for countries where they're allowed.
- **Keep listings in the repo** (`fastlane/metadata/android/<locale>/` via `supply`, or Triple-T `src/main/play/`) so they're reviewed in PRs and scanned by the audit.
- Chinese stores require their own listing, privacy policy URL, and screenshots in Simplified Chinese; write those neutral too.

## Answering a Regional Rejection

1. **Read the policy and the country or store** named in the Play policy email or the Chinese store's review report (which usually names the API call or string that failed).
2. **Pick one fix**: remove the country, gate the feature or ship a flavor without it, or obtain the license or filing.
3. **Search the code, resources, and every listing**, including SDK initialization order for privacy findings (the `store-compliance-pro` audit has the searches).
4. **Resubmit or appeal** through Play Console's Policy status page with what changed, and record the outcome in `docs/compliance/regions.md`.

## Common Pitfalls

- **Third-party AI brand names in strings or listings.**
- **"All countries" availability** with loans, gambling, or other licensed features.
- **Gating on locale or SIM** instead of the store country.
- **Mixing alpha-2 and alpha-3 codes** in a shared region table.
- **SDKs initialized in `Application.onCreate()`** before privacy consent; fatal for Chinese stores and a Data safety mismatch elsewhere.
- **One build with GMS for China**, or a `china` flavor that still pulls Firebase transitively.
- **Hiding a screen but not its shortcuts, notifications, or onboarding copy.**
- **Ignoring developer verification** for sideloaded or alternative-store builds.
- **No register**, so a region fix regresses on the next release.
