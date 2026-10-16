---
name: store-compliance-pro
description: Audits an Apple or Android app and its store listings for region-specific rejection risks — third-party AI brand mentions, generative-AI and licensing rules (China mainland ICP and CAC filings, game licenses, gambling, loans, VPNs), EU trader status, storefront-based feature gating, privacy consent order for Chinese Android stores, and metadata per storefront — and drives the fix after a regional App Store or Play rejection. Use before shipping to a new region, when adding an AI provider or regulated feature, or when a submission is rejected for one country or storefront.
license: MIT
metadata:
  author: AppBootstrapAI contributors
  version: "1.0"
  grounded_in: "App Review Guidelines (2.3.7, 4.1, 5, 5.1.2(i)), App Store Connect Help, Google Play Developer Policy Center, China's Interim Measures for Generative AI Services (2023) and MIIT app filing rules, KozBon's China storefront rejection over ChatGPT mentions"
---

Find what will get an app rejected or removed in a specific region before App Review does, and fix it when it already has. This is the deep companion to the always-on `apple-regional-compliance.md` and `android-regional-compliance.md` rules. The rules steer while writing; this skill audits the whole app plus its listing, and runs the rejection-response playbook.

Pick the mode from the request:

- **Audit**: before a release, before adding a storefront or country, or after adding an AI provider, payments, or another regulated feature. Run `references/audit.md` and check each in-scope region against `references/regions.md`.
- **Respond**: a submission was rejected or removed for a region. Follow `references/rejection-response.md`: classify the finding, choose a fix, sweep the app and listing, and draft the reply.
- **Set up**: no register exists yet. Create `docs/compliance/regions.md` and the `RegionPolicy` seam per `references/rejection-response.md` ("Register and policy seam").

If doing a partial task, load only the relevant reference file.

## Core Instructions

- **Region is decided per storefront, and the store decides.** Legal scope follows the App Store storefront or the Play account country, never device locale, SIM, or IP. Gating on locale is a finding.
- **The listing is part of the submission.** Audit metadata (name, subtitle, keywords, descriptions, promotional text, release notes, screenshots, previews) in every locale, and remember an unlocalized storefront shows the primary language.
- **Third-party AI brands are the top regional trigger.** ChatGPT, OpenAI, Claude, Anthropic, Gemini, Grok, Copilot, DeepSeek, Llama, and similar names in user-facing strings or metadata are a China rejection and a trademark risk everywhere. Code identifiers and dependency names are fine; consent screens may name the provider but must be region-gated with the feature.
- **One policy seam.** Regulated features ask a single injected `RegionPolicy`. Scattered country-code comparisons, or none at all, are findings.
- **Prefer the fix that removes the risk.** Excluding a storefront, or a build flavor without the feature, beats runtime gating when the law forbids the feature outright; runtime gating still ships the strings and SDKs.
- **Never invent a license or filing number**, never advise misleading reviewers, and never suggest geo-evasion (VPN-only detection, hiding features from review accounts). Compliance claims in review notes must be true.
- **Mark uncertainty.** Regulations change; cite the guideline or policy section and say when a requirement should be re-checked against the current text.
- **Severity by consequence**: blocking (will be rejected or removed in a storefront you ship to: AI brand mentions for China, missing ICP or game license, missing EU trader status, licensed feature without a license, data collected before consent on Chinese Android stores) > exposure (gated on locale instead of storefront, unknown storefront fails open, regulated feature reachable from a shortcut or notification, no register) > hygiene (provider names in strings that are currently gated, a register missing a "last verified" date).
- Cross-reference, don't duplicate: age ratings and privacy manifests go to `apple-testflight-deployment.md`; Data safety to `android-play-beta-deployment.md`; AI consent and provider wiring to `apple-foundation-models.md` and `android-ai-best-practices.md`; generic strings to the localization rules.

## Output Format

**Audit mode:** a region table first (storefront or country · shipping? · requirements · status), then findings grouped by severity. Each finding gives the location (file:line, or the metadata field and locale), the region and the rule or guideline it breaks, why review will catch it, and the fix with before/after. End with the scan counts and the first three fixes.

**Respond mode:** the rejection classified (region, guideline, trigger), the chosen fix and why, every location changed, the review-notes text, the Resolution Center or Play appeal reply, and the register entry.

Example finding:

### Blocking — China mainland: third-party AI brand in UI and metadata

**`Localizable.xcstrings` key `chat.title` reads "Ask ChatGPT", and the English description says "Powered by ChatGPT". The China storefront has no Simplified Chinese localization, so App Review there reads the English text. Generative-AI services need a CAC filing in China and ChatGPT has none (Guideline 5).**

```swift
// Before
static let title = LocalizedStringResource("chat.title", defaultValue: "Ask ChatGPT")

// After — generic label; the provider is named only on the region-gated consent screen
static let title = LocalizedStringResource("chat.title", defaultValue: "Ask the AI assistant")
```

Then either exclude China mainland in Pricing and Availability, or gate the feature with `RegionPolicy.allows(.externalAIProviders)` and say so in the review notes. Remove "Powered by ChatGPT" from every metadata locale and from screenshot 3.

End of example.

## References

- `references/regions.md` — per-region requirements for both stores: China mainland (Apple and Chinese Android stores), the EU, Japan, South Korea, age-assurance regions, and licensed categories, with where each is declared.
- `references/audit.md` — scan commands for AI brand mentions in code, strings, and metadata; storefront-gating checks; consent-before-collection checks for Android; and an App Store Connect / Play Console checklist.
- `references/rejection-response.md` — classifying a regional rejection, choosing among exclude / gate / license, the sweep, reply and review-notes templates, and the register and `RegionPolicy` seam.
