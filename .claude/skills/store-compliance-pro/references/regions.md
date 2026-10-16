# Regional Requirements

What each region needs, for both stores, and where it's declared. Requirements change; each row is a prompt to check the current guideline or policy, not a substitute for it. "Apple" means App Store Connect; "Play" means Play Console.

## China mainland

The region with the most requirements, and the one where foreign AI features fail most often.

| Requirement | Apple | Android |
|---|---|---|
| **ICP filing (备案)** with MIIT | Filing number in App Information; no number, no China storefront | Required by every Chinese store |
| **Generative AI** (CAC filing under the 2023 Interim Measures) | Unfiled services (ChatGPT, Claude, Gemini, and others) rejected under Guideline 5; mentions alone are enough | Same rule, enforced by each store's review |
| **Third-party AI brand mentions** | UI, onboarding, settings, and every metadata field visible on the storefront | UI and listings |
| **Games** | NPPA approval number (版号) in App Store Connect | Required by every store |
| **VoIP calling** | CallKit must be disabled for China | Store-specific; usually needs a telecom license |
| **Maps** | Approved borders and names; GCJ-02 coordinates (MapKit handles it in China) | Same; use a domestic map SDK |
| **Privacy consent order** | Standard Apple privacy review | Automated checks: no device identifiers, app list, clipboard, location, or SDK init before the user accepts the privacy policy |
| **Google services** | n/a | No GMS, Play Billing, Firebase, or AICore; ship a GMS-free flavor |
| **Other restricted** | Unlicensed VPNs, crypto exchanges and mining, gambling, content on politically sensitive topics | Same |
| **Distribution** | China storefront | Huawei AppGallery, Xiaomi, OPPO, vivo, Honor, Tencent MyApp; often a software copyright certificate (软著) and a mainland publisher |

**Apple Intelligence and Foundation Models** availability varies by region; treat on-device AI as a runtime capability (`SystemLanguageModel.default.availability`), never as present in China.

**Realistic options for a foreign app with AI features:** exclude China mainland; or ship without the AI feature there (storefront gating on Apple, a `china` flavor on Android) with neutral strings and metadata; or partner with a provider holding a Chinese filing and display its filing information.

## European Union

| Requirement | Apple | Android |
|---|---|---|
| **DSA trader status** | Declare in App Store Connect ▸ Business; non-traders declare too. Undeclared apps were removed from EU storefronts in 2025. | Declare and verify in Play Console; unverified apps lose EU distribution |
| **DMA** alternative distribution and payments | Optional; alternative terms addendum, notarization for alternative marketplaces | Optional; alternative billing and user-choice billing programs |
| **GDPR** | Consent and data-subject rights; privacy manifest and label must match | Data safety form must match |
| **Loot boxes** | Odds disclosure required globally (Guideline 3.1.1); Belgium treats paid random rewards as gambling | Same; check Belgium and the Netherlands |

## Other regions

| Region | Requirement |
|---|---|
| **Japan** | Mobile Software Competition Act (in force December 2025): alternative stores and payments on both platforms. Changes commercial terms, not review content. |
| **South Korea** | Games need a GRAC rating. Alternative billing allowed on both stores under the Telecommunications Business Act. |
| **Vietnam** | Games need a local license (G1) before release on the App Store. |
| **Australia, Brazil, Singapore, Utah, Louisiana** | Age assurance and age-gated social features. Apple: `DeclaredAgeRange` and the social-media capability question (see `apple-testflight-deployment.md`). Android: Play Age Signals API and the content rating questionnaire. |
| **Brazil, Indonesia, Singapore, Thailand** | Android developer verification from September 2026, then worldwide: certified devices block apps from unverified developers, including sideloaded builds. |
| **India, Indonesia, Kenya, Nigeria, Pakistan, the Philippines, Thailand** | Play's personal loan policy has country-specific licensing and disclosure requirements. |
| **Russia, Iran, and other sanctioned markets** | Storefront and payment availability limited by sanctions; don't add a storefront without legal review. |

## Categories licensed per jurisdiction

These need a license or registration in *each* country where they're offered, on both stores. Restrict availability to licensed countries and say so in review notes.

- Real-money gambling, lotteries, sports betting, and daily fantasy (Apple 5.3; Play's gambling policy with an application per country).
- Personal loans and lending (Apple 3.2.2; Play's personal loan policy).
- Cryptocurrency exchanges, wallets that trade, and mining (Apple 3.1.5; Play's financial services policy).
- VPN services (Apple 5.4, which requires an organization account; licenses in China, Russia, the UAE, and others).
- Medical devices and diagnostic claims (FDA, EU MDR, and others; Apple 1.4.1).
- Telehealth, prescriptions, and pharmacy (local medical licensing).

## Worldwide rules that become regional triggers

- **Trademarks in metadata** (Apple 2.3.7, 4.1, 5.2; Play Metadata and Impersonation policies): another company's product name in the app name, subtitle, keywords, icon, or screenshots.
- **Third-party AI data sharing** (Apple 5.1.2(i), November 2025): disclose the provider and get explicit permission before sending personal data. Play: Data safety disclosure and consent.
- **AI-generated content** (Play AI-Generated Content policy): in-app reporting of offensive output and safeguards against restricted content. Apple: user-generated content rules (1.2) apply to AI chat.
