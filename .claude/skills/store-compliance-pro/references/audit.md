# Audit

Run from the repo root. Each check prints findings, not whole files. Report counts per check in the summary.

## 1. Inventory the regions

Find where availability and listings are recorded before scanning anything:

```bash
# Register and listing sources in the repo
ls docs/compliance/regions.md 2>/dev/null || echo "no register"
find . -path '*/fastlane/metadata/*' -maxdepth 6 -type d -not -path '*/node_modules/*' | head -50
find . -path '*/src/*/play/listings/*' -type d | head -20      # Triple-T layout
```

If availability lives only in App Store Connect or Play Console, ask the user for the storefront or country list, or for a screenshot of Pricing and Availability / Countries and regions. Don't guess.

## 2. Third-party AI brand mentions

User-facing strings and metadata only. Code identifiers, package names, and comments are allowed.

```bash
AI_BRANDS='ChatGPT|OpenAI|GPT-[0-9]|Claude|Anthropic|Gemini|Bard|Grok|xAI|Copilot|DeepSeek|Llama|Mistral|Perplexity|Midjourney'

# Apple: string catalogs, legacy strings, Info.plist purpose strings
rg -n -i -e "$AI_BRANDS" -g '*.xcstrings' -g '*.strings' -g '*.stringsdict' -g 'Info.plist' -g 'InfoPlist.*'

# Apple: SwiftUI literals that bypass the strings facade
rg -n -e "(Text|Label|Button|navigationTitle|accessibilityLabel)\(\"[^\"]*($AI_BRANDS)" -g '*.swift'

# Android: resources and Compose literals
rg -n -i -e "$AI_BRANDS" -g 'strings.xml' -g 'plurals.xml' -g 'arrays.xml'
rg -n -e "Text\(\"[^\"]*($AI_BRANDS)" -g '*.kt'

# Store metadata (fastlane deliver / supply, Triple-T)
rg -n -i -e "$AI_BRANDS" -g '*.txt' fastlane/ 2>/dev/null
rg -n -i -e "$AI_BRANDS" --glob '**/play/**' . 2>/dev/null
```

`-i` catches lowercase uses but flags words like "claude" as a first name; read each hit. For each hit, record whether it sits behind a region gate, and in which locale.

Screenshots and previews can't be grepped. List them per locale and ask the user to confirm none shows a provider badge, logo, or name.

## 3. Region gating

```bash
# Apple: how is region detected?
rg -n 'Storefront\.(current|updates)|SKPaymentQueue.*storefront' -g '*.swift'
rg -n 'Locale\.(current|autoupdatingCurrent)\.(region|regionCode)|TimeZone\.current' -g '*.swift'

# Android: how is region detected?
rg -n 'getBillingConfigAsync|BillingConfig' -g '*.kt'
rg -n 'Locale\.getDefault\(\)\.country|simCountryIso|networkCountryIso' -g '*.kt'

# Scattered country comparisons outside the policy type
rg -n '"(CHN|CN|KOR|KR|VNM|VN|RUS|RU)"' -g '*.swift' -g '*.kt' | rg -v 'RegionPolicy'

# Android: market flavors and per-flavor dependencies
rg -n 'productFlavors|flavorDimensions|Implementation\(' -g '*.gradle.kts'
```

Findings:

- **Locale, time zone, SIM, or IP used for a legal decision**: exposure. Replace with the storefront or Play country.
- **Country codes compared outside `RegionPolicy`**: exposure. Move into the policy.
- **Unknown storefront returns "allowed"** for a regulated feature: exposure. Fail closed.
- **No gating at all** while a restricted storefront is in availability: blocking.
- **A gated feature still reachable** from App Shortcuts / `AppShortcutsProvider`, widgets, notifications, Spotlight, deep links, or Android shortcuts: exposure. Search for the feature's entry types and check each one goes through the policy.

## 4. Android: consent before collection (Chinese stores, Data safety)

```bash
# SDK init and identifier reads in Application / ContentProvider / startup initializers
rg -n 'class .*: Application\(' -g '*.kt'
rg -n 'initialize\(|FirebaseApp|Firebase\.|Analytics|Crashlytics|Sentry|AppsFlyer|Adjust' -g '*Application*.kt' -g '*Initializer*.kt'
rg -n 'ANDROID_ID|getDeviceId|getImei|macAddress|getInstalledPackages|getInstalledApplications|ClipboardManager|requestLocationUpdates' -g '*.kt'
rg -n 'androidx.startup|InitializationProvider' -g 'AndroidManifest.xml'
```

Anything that runs before the privacy-policy acceptance on first launch is blocking for Chinese stores and a Data safety risk on Play. Fix by deferring init behind a consent flag persisted in DataStore.

For the `china` flavor, confirm no Google dependency reaches the classpath:

```bash
./gradlew :app:dependencies --configuration chinaReleaseRuntimeClasspath | rg -i 'gms|firebase|play-services|billing'
```

## 5. Licensed categories

```bash
rg -n -i 'bet|wager|casino|lottery|sweepstake|loan|lend|crypto|wallet|vpn|NEVPNManager|VpnService|CallKit|CXProvider|diagnos' \
   -g '*.swift' -g '*.kt' -g '*.xcstrings' -g 'strings.xml' | head -100
```

For each category present, check that availability is limited to licensed regions and that the review notes or Play declarations say so.

## 6. Store-console checklist

Ask the user to confirm, or check from screenshots:

**App Store Connect**
- Pricing and Availability: storefront list matches the register.
- App Information: China ICP filing number (if China ships); game license numbers where required.
- Business: EU trader status declared.
- Age rating questionnaire and social-media capability answer are current.
- App Review notes describe region gating and any AI provider consent.
- Every metadata locale, plus the primary locale shown on unlocalized storefronts, is neutral.

**Play Console**
- Countries/regions matches the register.
- App content: Data safety, Financial features, Health, Government, News, and gambling declarations answered for every country shipped.
- Account details: DSA trader status verified.
- Custom store listings: provider claims only in countries where allowed.
- Developer verification complete if any build is distributed outside Play.

## Summary table

| Check | Count |
|---|---|
| AI brand mentions in user-facing strings | |
| AI brand mentions in metadata (by locale) | |
| Ungated regulated features | |
| Locale/SIM/IP-based legal decisions | |
| Country checks outside `RegionPolicy` | |
| Pre-consent SDK inits / identifier reads (Android) | |
| Licensed categories without region limits | |
| Console items unconfirmed | |
