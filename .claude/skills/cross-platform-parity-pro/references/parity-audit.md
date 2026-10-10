# Parity audit

Two passes: **mechanical** (scripts diff the shared vocabularies) and **behavioral** (compare each feature against its spec). Run the mechanical pass first; its counts decide where to read code.

Adjust paths to the repo's layout. The scripts assume `apple/` and `android/` at the root and print only differences.

## Mechanical checks

### String keys

```python
#!/usr/bin/env python3
"""Diff string keys between .xcstrings catalogs and Android strings.xml (dots → underscores)."""
import glob, json, sys
import xml.etree.ElementTree as ET

apple = set()
for path in glob.glob("apple/**/*.xcstrings", recursive=True):
    if "InfoPlist" in path:           # Info.plist keys are Apple-only by design
        continue
    with open(path, encoding="utf-8") as fh:
        apple |= {k.replace(".", "_") for k in json.load(fh).get("strings", {})}

android = set()
for path in glob.glob("android/**/src/main/res/values/*.xml", recursive=True):
    root = ET.parse(path).getroot()
    for el in root:
        if el.tag in ("string", "plurals", "string-array") and el.get("translatable") != "false":
            android.add(el.get("name"))

only_apple, only_android = sorted(apple - android), sorted(android - apple)
print(f"Apple-only keys ({len(only_apple)}):", *only_apple, sep="\n  ")
print(f"Android-only keys ({len(only_android)}):", *only_android, sep="\n  ")
sys.exit(1 if only_apple or only_android else 0)
```

Allow intentional platform-only keys with an allowlist file (e.g. `shared/strings/platform-only.txt`) rather than deleting them from the report.

### Icon vocabulary

```bash
# Apple: cases of the AppIcon enum. Android: properties of the AppIcons object.
rg -o --no-filename '^\s*case\s+(\w+)' -r '$1' apple/ -g 'AppIcon*.swift' | tr '[:upper:]' '[:lower:]' | sort -u > /tmp/icons-apple
rg -o --no-filename '^\s*val\s+(\w+)\s*:\s*ImageVector' -r '$1' android/ -g 'AppIcons*.kt' | tr '[:upper:]' '[:lower:]' | sort -u > /tmp/icons-android
diff /tmp/icons-apple /tmp/icons-android
```

Names are compared case-insensitively (`.delete` ↔ `Delete`). Raw `systemName:` strings or `Icons.Default.*` in feature code bypass both vocabularies — count them too (the design-system skills' audit searches).

### Analytics events

```bash
# Generated APIs are the source; string literals at call sites are findings on their own.
rg -n 'track\("|logEvent\("|analytics\.log\("' apple/ android/ -g '!**/Generated/**' -g '!**/build/**'
```

When both sides generate from `shared/analytics/events.yaml`, diff the generated event names against the schema; any event referenced in code but absent from the schema is drift.

### Feature flags / remote config

```bash
rg -o --no-filename '"([a-z0-9_]+)"' -r '$1' apple/ -g '*Flags*.swift' -g '*RemoteConfig*.swift' | sort -u > /tmp/flags-apple
rg -o --no-filename '"([a-z0-9_]+)"' -r '$1' android/ -g '*Flags*.kt' -g '*RemoteConfig*.kt' | sort -u > /tmp/flags-android
diff /tmp/flags-apple /tmp/flags-android
```

Also compare defaults: the same key with different defaults ships different behavior until remote config loads.

### Deep links

- Apple: paths in `apple-app-site-association` (`applinks.details[].components`) and the routes handled in `onOpenURL` / the router.
- Android: `<intent-filter android:autoVerify="true">` `pathPattern`s / `pathPrefix`es in `AndroidManifest.xml`, and `deepLinks` in Navigation Compose destinations.
- Every route in the shared route table must appear on both, or be marked platform-only.

### Contracts

- API: is there one `openapi.yaml`, and do both platforms generate from it? Search for hand-written DTOs duplicating generated ones (`struct .*Response: Decodable` / `data class .*Response`).
- Tokens: are hex values defined in both design-system modules, or generated from `shared/design-tokens`? `rg 'Color\(0x|#[0-9A-Fa-f]{6}' android/core/designsystem` and the Apple asset-catalog color sets vs the tokens file.

## Behavioral checklist (per feature)

For each feature in `docs/parity.md` (or each top-level screen if there's no parity file yet):

- [ ] Same states reachable (loading / empty / content / error / stale) with equivalent copy.
- [ ] Same user actions available; platform-specific gestures have equivalents (swipe on iOS ↔ swipe or menu on Android).
- [ ] Same validation rules and error messages.
- [ ] Same offline behavior and refresh semantics.
- [ ] Same analytics events at the same moments, same properties.
- [ ] Same flags gate the same things.
- [ ] Deep links land on the same screen with the same back behavior expectations (platform-native back).
- [ ] Accessibility: every action reachable by VoiceOver and TalkBack; labels say the same thing.
- [ ] Presentation follows each platform's conventions (not a copy of the other).

## Parity file format

```markdown
# Platform parity

| Feature | Apple | Android | Notes |
|---|---|---|---|
| Task list | ✅ 2.3 | ✅ 2.3 | |
| Task sharing | ✅ 2.4 | 🚧 #412 | |
| Home-screen widget | ✅ 2.1 | ⏳ | Glance widget planned |
| Live Activity | ✅ 2.2 | — | Apple only |
| Quick Settings tile | — | ✅ 2.2 | Android only |

✅ shipped (version) · 🚧 in progress (issue) · ⏳ planned · — not applicable

## Intentional differences
- Completion gesture: swipe on iOS; checkbox + swipe on Android.
```

## Running the checks in CI

Wire the string-key and icon diffs as a job that runs on changes to `shared/**`, either platform's string/icon files, or `docs/parity.md`. Start it as non-blocking and make it blocking once the backlog is cleared — same adoption curve as the linting rules.
