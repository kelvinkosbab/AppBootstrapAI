#!/usr/bin/env python3
"""AppBootstrapAI installer — `audit` action.

Read-only health check of a target repo against the bundle: is the bundle
installed and current, and where does the code break the rules it ships? Each
finding names the rule it comes from and the skill to load for a deep review,
so an agent of any vendor can turn the output into a focused audit instead of
reading the whole tree.

The checks are deliberately cheap and high-signal (regexes and file-presence
tests). They find *where to look*; judgment comes from the skills. See
playbooks/sync-and-audit.md for the agent workflow built on top of this.

Invoked by install.sh's `audit` verb:

    python3 lib/audit.py --target DIR --bundle /abs/bundle/root \\
        --bundle-commit SHA --recommended "<cats>" --all "<cats>" \\
        [--json] [--fail-on high|medium|low] \\
        [--baseline PATH | --no-baseline] [--write-baseline [--baseline-reason TEXT]] \\
        [--no-install-check] [--steering-only]

--no-install-check drops the "not installed / outdated" findings, for auditing
a repo without adopting the bundle (playbooks/audit.md).

The repo's own AI steering files (CLAUDE.md, AGENTS.md, Cursor/Copilot/Kiro
rules, skills, settings) are checked too; see lib/steering.py. Their findings
have ids starting with `steering-`, and the `steering` key inventories the
files. --steering-only skips the code checks and reports just those.

A baseline (default .claude/appbootstrap-audit-baseline.json) records
accepted findings as per-file counts, each with a reason. Baselined findings
are reported separately and never trip --fail-on, so CI fails only on new
problems. Counts per file (not line numbers) keep it stable as code moves.

Exit code: 0, or 2 when --fail-on is set and a non-baselined finding at or
above that severity exists.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
from dataclasses import dataclass, field

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import recommend  # noqa: E402  (sibling module; shares detection logic)
import steering  # noqa: E402  (AI steering-file checks)

SEVERITIES = ("high", "medium", "low")
SEV_RANK = {s: i for i, s in enumerate(SEVERITIES)}
MAX_LOCATIONS = 5
MAX_READ_BYTES = 2_000_000
DEFAULT_BASELINE = os.path.join(".claude", "appbootstrap-audit-baseline.json")
# Install-state findings are fixed by running the installer, never accepted.
UNBASELINABLE = {"bundle-outdated", "bundle-not-installed"}

# Agent-config dirs hold the bundle's own rule text, which quotes every
# anti-pattern on purpose. Never scan them.
SKIP_DIRS = recommend.SKIP_DIRS | {".claude", ".cursor", ".kiro", ".gemini", ".codex"}

SCAN_EXTS = {".swift", ".m", ".mm", ".h", ".kt", ".kts", ".gradle", ".xml",
             ".plist", ".xcstrings", ".strings", ".json", ".properties", ".txt"}

# Files whose embedded API keys are public by design (Firebase client config).
PUBLIC_KEY_FILES = {"google-services.json", "GoogleService-Info.plist"}

SECRET_PATTERN = re.compile(r"AIza[0-9A-Za-z_\-]{35}|sk-ant-[A-Za-z0-9_\-]{20,}|\bsk-(?:proj-)?[A-Za-z0-9]{32,}")

AI_BRANDS = r"\b(ChatGPT|OpenAI|Anthropic|Claude|Gemini|Grok|Copilot)\b"


@dataclass
class Check:
    id: str
    title: str
    severity: str
    platform: str            # apple | android | any
    exts: frozenset
    pattern: re.Pattern
    rule: object             # rule filename, or {"apple": …, "android": …} for "any" checks
    skill: str | None
    fix: str
    skip_tests: bool = False
    path_ok: object = None   # optional callable(rel_path) -> bool


@dataclass
class Finding:
    id: str
    title: str
    severity: str
    rule: str | None
    skill: str | None
    fix: str
    count: int = 0
    locations: list = field(default_factory=list)
    all_locations: list = field(default_factory=list)
    baselined: int = 0

    def add(self, loc: str) -> None:
        self.count += 1
        self.all_locations.append(loc)
        if len(self.locations) < MAX_LOCATIONS:
            self.locations.append(loc)


def _loc_file(loc: str) -> str:
    """'Sources/A.swift:12' -> 'Sources/A.swift'; non-line locations stay as is."""
    head, sep, tail = loc.rpartition(":")
    return head if sep and tail.isdigit() else loc


def _per_file(f: Finding) -> dict:
    counts: dict = {}
    for loc in f.all_locations:
        counts[_loc_file(loc)] = counts.get(_loc_file(loc), 0) + 1
    return counts


def _exts(*e):
    return frozenset(e)


def _is_test(rel: str) -> bool:
    low = rel.lower()
    base = os.path.basename(rel)
    return ("/tests/" in "/" + low or "/test/" in "/" + low or "/androidtest/" in "/" + low
            or base.endswith(("Tests.swift", "Test.swift", "Test.kt", "Tests.kt")))


def _in_theme(rel: str) -> bool:
    low = rel.lower()
    return "designsystem" in low or "/theme/" in low or "/ui/theme" in low


def _is_listing(rel: str) -> bool:
    return rel.startswith("fastlane/metadata/") or "/src/main/play/" in "/" + rel


SWIFT = _exts(".swift")
OBJC_SWIFT = _exts(".swift", ".m", ".mm")
KOTLIN = _exts(".kt")

CHECKS = [
    # --- Apple ---------------------------------------------------------------
    Check("swift-unchecked-sendable", "`@unchecked Sendable` silences data-race checking",
          "high", "apple", SWIFT, re.compile(r"@unchecked\s+Sendable"),
          "apple-swift6-strict-concurrency.md", "swift-concurrency-pro",
          "Redesign the type (actor, value type, or @MainActor) instead of opting out."),
    Check("swift-force-try", "`try!` crashes on the first thrown error",
          "high", "apple", SWIFT, re.compile(r"\btry!"),
          "apple-swift6-strict-concurrency.md", "swift-error-handling-pro",
          "Use do/catch and log the error.", skip_tests=True),
    Check("swift-uiscreen-main", "`UIScreen.main` is wrong on multi-display and resizable apps",
          "high", "apple", OBJC_SWIFT, re.compile(r"UIScreen\.main\b|\[UIScreen mainScreen\]"),
          "apple-adaptive-layout.md", "swift-adaptive-layout-pro",
          "Read the screen from the window scene, and scale from traitCollection.displayScale."),
    Check("swift-idiom-layout", "Layout branches on device idiom instead of size class",
          "medium", "apple", OBJC_SWIFT, re.compile(r"userInterfaceIdiom\s*==|UIUserInterfaceIdiomPad"),
          "apple-adaptive-layout.md", "swift-adaptive-layout-pro",
          "Branch on horizontalSizeClass / available space."),
    Check("swift-dispatch-main", "`DispatchQueue.main.async` instead of structured concurrency",
          "medium", "apple", SWIFT, re.compile(r"DispatchQueue\.main\.async"),
          "apple-swift6-strict-concurrency.md", "swift-concurrency-pro",
          "Use @MainActor isolation and async/await."),
    Check("swift-print", "`print()` / `NSLog` in shipping code",
          "medium", "apple", OBJC_SWIFT, re.compile(r"^\s*(print|debugPrint|NSLog)\s*\("),
          "apple-logging-strategy.md", "swift-logging-pro",
          "Log through os.Logger with a subsystem, category, and privacy markers.", skip_tests=True),
    Check("swift-fixed-font", "Fixed-size fonts ignore Dynamic Type",
          "medium", "apple", OBJC_SWIFT, re.compile(r"\.system\(size:|systemFontOfSize:"),
          "apple-accessibility-best-practices.md", "swift-accessibility-pro",
          "Use text styles (.body, .headline) or Font.custom(_:size:relativeTo:)."),
    Check("swift-raw-symbol", "Raw SF Symbol strings at call sites",
          "low", "apple", SWIFT, re.compile(r"systemName:\s*\""),
          "apple-iconography.md", "swift-design-system-pro",
          "Route symbols through a typed AppIcon facade with a resolves-on-min-OS test.",
          path_ok=lambda rel: not _in_theme(rel)),
    Check("swift-literal-color", "Literal colors in feature code",
          "low", "apple", SWIFT, re.compile(r"Color\(\s*red:|UIColor\(\s*red:|Color\(hex"),
          "apple-design-system.md", "swift-design-system-pro",
          "Use role-named tokens built on semantic colors.",
          path_ok=lambda rel: not _in_theme(rel)),
    Check("swift-text-literal", "Hardcoded English in `Text(\"…\")`",
          "low", "apple", SWIFT, re.compile(r"\bText\(\s*\"[A-Za-z][^\"]*\s[^\"]*\"\s*\)"),
          "apple-localization-best-practices.md", "swiftui-pro",
          "Route UI strings through the typed Strings facade.", skip_tests=True),

    # --- Android -------------------------------------------------------------
    Check("kt-global-scope", "`GlobalScope` outlives every lifecycle",
          "high", "android", KOTLIN, re.compile(r"\bGlobalScope\b"),
          "android-coroutines-best-practices.md", "android-coroutines-pro",
          "Use viewModelScope, lifecycleScope, an injected app scope, or WorkManager."),
    Check("kt-run-blocking", "`runBlocking` in app code blocks the caller",
          "medium", "android", KOTLIN, re.compile(r"\brunBlocking\b"),
          "android-coroutines-best-practices.md", "android-coroutines-pro",
          "Make the caller suspend or launch in a proper scope.", skip_tests=True),
    Check("kt-collect-as-state", "`collectAsState()` keeps collecting in the background",
          "medium", "android", KOTLIN, re.compile(r"\.collectAsState\("),
          "android-compose-best-practices.md", "android-compose-pro",
          "Use collectAsStateWithLifecycle()."),
    Check("kt-android-log", "`android.util.Log` instead of Timber",
          "medium", "android", KOTLIN, re.compile(r"^\s*import android\.util\.Log\b|\bLog\.[vdiwe]\("),
          "android-logging-strategy.md", None,
          "Log through Timber with a release tree that strips debug logs.", skip_tests=True),
    Check("kt-announce", "`announceForAccessibility` is deprecated (Android 16)",
          "medium", "android", KOTLIN, re.compile(r"announceForAccessibility\("),
          "android-accessibility-best-practices.md", "android-accessibility-pro",
          "Use liveRegion, paneTitle, or stateDescription semantics."),
    Check("kt-literal-color", "Literal colors in feature composables",
          "low", "android", KOTLIN, re.compile(r"\bColor\(0x[0-9A-Fa-f]{6,8}\)"),
          "android-design-system.md", "android-design-system-pro",
          "Read MaterialTheme.colorScheme roles or extended tokens.",
          path_ok=lambda rel: not _in_theme(rel)),
    Check("kt-empty-content-description", "`contentDescription = \"\"` instead of null",
          "low", "android", KOTLIN, re.compile(r"contentDescription\s*=\s*\"\""),
          "android-iconography.md", "android-accessibility-pro",
          "Pass null for decorative icons; a string resource for meaningful ones."),
    Check("kt-kapt", "kapt instead of KSP",
          "low", "android", _exts(".kts", ".gradle"), re.compile(r"\bkapt\(|kotlin-kapt|kotlin\(\"kapt\"\)"),
          "android-gradle-conventions.md", "android-gradle-architecture-pro",
          "Move annotation processors (Hilt, Room, Moshi) to KSP."),
    Check("kt-icons-extended", "`material-icons-extended` pulled in for a few glyphs",
          "low", "android", _exts(".kts", ".gradle", ".toml"), re.compile(r"material-icons-extended"),
          "android-iconography.md", "android-design-system-pro",
          "Import the Material Symbols you use as vector drawables behind AppIcons."),
    Check("android-orientation-lock", "Orientation lock (ignored on large screens since Android 16)",
          "medium", "android", _exts(".xml"), re.compile(r"android:screenOrientation=\"(portrait|landscape|sensorPortrait)\""),
          "android-large-screen-best-practices.md", "android-adaptive-layout-pro",
          "Remove the lock and adapt the layout with window size classes.",
          path_ok=lambda rel: rel.endswith("AndroidManifest.xml")),

    # --- Both ----------------------------------------------------------------
    Check("hardcoded-secret", "API key or token committed in source",
          "high", "any", _exts(".swift", ".m", ".kt", ".kts", ".gradle", ".plist", ".xml",
                               ".json", ".properties"),
          SECRET_PATTERN, None, None,
          "Remove it, rotate the key, and route calls through a backend or Firebase App Check.",
          path_ok=lambda rel: os.path.basename(rel) not in PUBLIC_KEY_FILES),
    Check("ai-brand-in-ui", "Third-party AI brand name in user-facing text",
          "medium", "any", _exts(".swift", ".kt", ".xml", ".xcstrings", ".strings", ".txt"),
          re.compile(r"\"[^\"\n]*" + AI_BRANDS + r"[^\"\n]*\"|>[^<\n]*" + AI_BRANDS + r"[^<\n]*<"),
          {"apple": "apple-regional-compliance.md", "android": "android-regional-compliance.md"},
          "store-compliance-pro",
          "Describe the capability (\"AI assistant\"); name a provider only on the region-gated consent screen.",
          path_ok=lambda rel: not rel.endswith(".txt") or _is_listing(rel)),
]

COMMENT_PREFIXES = ("//", "*", "/*", "#", "<!--")


def scan_sources(target: str, platforms: set, findings: dict) -> dict:
    """Walk the tree once, applying line checks. Returns facts for structural checks."""
    facts = {"source_files": 0, "uses_userdefaults": False, "privacy_manifests": [],
             "scene_manifest": False, "swiftui_app": False, "uikit_delegate": False,
             "android_manifests": [], "launcher_icons": []}
    active = [c for c in CHECKS if c.platform == "any" or c.platform in platforms]

    for root, dirs, files in os.walk(target):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.endswith(".xcworkspace")
                   and not d.endswith(".xcodeproj")]
        for fn in files:
            path = os.path.join(root, fn)
            rel = os.path.relpath(path, target).replace(os.sep, "/")
            ext = os.path.splitext(fn)[1].lower()
            if fn == "PrivacyInfo.xcprivacy":
                facts["privacy_manifests"].append(path)
            if ext not in SCAN_EXTS and ext != ".toml":
                continue
            if ext in (".swift", ".m", ".mm", ".kt"):
                facts["source_files"] += 1
            try:
                if os.path.getsize(path) > MAX_READ_BYTES:
                    continue
                with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                    text = fh.read()
            except OSError:
                continue
            _collect_facts(fn, rel, ext, text, facts)

            applicable = [c for c in active if ext in c.exts
                          and not (c.skip_tests and _is_test(rel))
                          and (c.path_ok is None or c.path_ok(rel))]
            if not applicable:
                continue
            for lineno, line in enumerate(text.splitlines(), 1):
                stripped = line.lstrip()
                is_comment = stripped.startswith(COMMENT_PREFIXES)
                for c in applicable:
                    if is_comment and c.id != "hardcoded-secret":
                        continue
                    if c.pattern.search(line):
                        _finding(findings, c, ext).add(f"{rel}:{lineno}")
    return facts


def _collect_facts(fn, rel, ext, text, facts) -> None:
    if ext == ".swift":
        if "UserDefaults" in text or "@AppStorage" in text:
            facts["uses_userdefaults"] = True
        if re.search(r":\s*App\s*\{", text):
            facts["swiftui_app"] = True
        if "@UIApplicationMain" in text or re.search(r"\bUIApplicationDelegate\b", text):
            facts["uikit_delegate"] = True
    if ext == ".plist" and "UIApplicationSceneManifest" in text:
        facts["scene_manifest"] = True
    if fn == "AndroidManifest.xml":
        facts["android_manifests"].append((rel, text))
    if ext == ".xml" and "<adaptive-icon" in text:
        facts["launcher_icons"].append((rel, text))


ANDROID_EXTS = {".kt", ".kts", ".gradle", ".xml", ".toml"}


def _finding(findings: dict, c: Check, ext: str) -> Finding:
    if c.id not in findings:
        rule = c.rule
        if isinstance(rule, dict):
            rule = rule["android" if ext in ANDROID_EXTS else "apple"]
        findings[c.id] = Finding(c.id, c.title, c.severity, rule, c.skill, c.fix)
    return findings[c.id]


def _structural(target, platforms, facts, findings, kind) -> None:
    def add(id_, title, sev, rule, skill, fix, loc):
        f = findings.setdefault(id_, Finding(id_, title, sev, rule, skill, fix))
        f.add(loc)

    has_xcodeproj = bool(glob.glob(os.path.join(target, "**", "*.xcodeproj"), recursive=True))
    if "apple" in platforms and has_xcodeproj:
        pbx = " ".join(_read(p) for p in glob.glob(
            os.path.join(target, "**", "*.xcodeproj", "project.pbxproj"), recursive=True))
        if "UIApplicationSceneManifest" in pbx:
            facts["scene_manifest"] = True
        if not facts["privacy_manifests"]:
            add("apple-no-privacy-manifest", "No PrivacyInfo.xcprivacy (App Store upload gate)",
                "high", "apple-testflight-deployment.md", None,
                "Add a privacy manifest declaring required-reason APIs and collected data.",
                "(app target)")
        elif facts["uses_userdefaults"] and not any(
                "NSPrivacyAccessedAPICategoryUserDefaults" in _read(p)
                for p in facts["privacy_manifests"]):
            add("apple-privacy-userdefaults", "UserDefaults used but not declared in the privacy manifest",
                "high", "apple-testflight-deployment.md", None,
                "Declare NSPrivacyAccessedAPICategoryUserDefaults with reason CA92.1.",
                os.path.relpath(facts["privacy_manifests"][0], target))
        if facts["uikit_delegate"] and not facts["swiftui_app"] and not facts["scene_manifest"]:
            add("apple-no-scene-lifecycle", "No UIScene lifecycle (apps won't launch on the iOS 27 SDK)",
                "high", "apple-adaptive-layout.md", "swift-adaptive-layout-pro",
                "Adopt UIScene: add a scene manifest and a UIWindowSceneDelegate.", "(app delegate)")

    if "apple" in platforms and facts["source_files"] and not _any_file(target, ".swiftlint.yml"):
        add("apple-no-swiftlint", "No SwiftLint configuration", "low",
            "apple-linting-strategy.md", None,
            "Add a .swiftlint.yml with the high-value opt_in_rules and run it with --strict in CI.",
            ".swiftlint.yml")

    if "android" in platforms:
        for rel, text in facts["android_manifests"]:
            if "<application" in text and "supportsRtl=\"true\"" not in text:
                add("android-no-rtl", "Manifest doesn't set android:supportsRtl=\"true\"", "low",
                    "android-localization-best-practices.md", None,
                    "Set supportsRtl on <application> and use start/end modifiers.", rel)
        for rel, text in facts["launcher_icons"]:
            if "<monochrome" not in text:
                add("android-icon-no-monochrome", "Adaptive launcher icon has no monochrome layer", "low",
                    "android-iconography.md", "android-design-system-pro",
                    "Add a <monochrome> layer so themed icons render correctly.", rel)
        if facts["source_files"] and not os.path.isfile(os.path.join(target, ".editorconfig")):
            add("android-no-ktlint-config", "No .editorconfig for ktlint", "low",
                "android-linting-strategy.md", None,
                "Add .editorconfig with ktlint_code_style and run ktlintCheck, detekt, and lintDebug in CI.",
                ".editorconfig")

    # A library never ships to a store, so it has no regions to record.
    if kind == "app" and platforms and facts["source_files"] and not os.path.isfile(
            os.path.join(target, "docs", "compliance", "regions.md")):
        rule = ("apple-regional-compliance.md" if "apple" in platforms
                else "android-regional-compliance.md")
        add("no-compliance-register", "No regional compliance register", "low", rule,
            "store-compliance-pro",
            "Record per-region availability and requirements in docs/compliance/regions.md.",
            "docs/compliance/regions.md")


def _read(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as fh:
            return fh.read(MAX_READ_BYTES)
    except OSError:
        return ""


def _any_file(target: str, name: str) -> bool:
    for root, dirs, files in os.walk(target):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        if name in files:
            return True
        if os.path.relpath(root, target).count(os.sep) >= 2:
            dirs[:] = []
    return False


def bundle_status(target, rec, bundle_commit):
    """Return (status dict, list of findings) for the install itself."""
    state = rec["state"]
    status = {"state": state, "installed_commit": None, "current_commit": bundle_commit,
              "up_to_date": None, "action": rec["action"], "command": rec["command"],
              "preview_command": rec["preview_command"]}
    out = []
    if state == "managed":
        try:
            with open(os.path.join(target, ".claude", ".appbootstrap-manifest.json")) as fh:
                status["installed_commit"] = json.load(fh).get("bundle_commit")
        except (OSError, ValueError):
            pass
        known = bundle_commit != "unknown" and status["installed_commit"] not in (None, "unknown")
        status["up_to_date"] = (status["installed_commit"] == bundle_commit) if known else None
        if status["up_to_date"] is False or rec["notes"]:
            f = Finding("bundle-outdated", "Installed bundle is behind the current bundle", "medium",
                        None, None, "Preview, then apply: " + rec["command_str"])
            f.add(".claude/.appbootstrap-manifest.json")
            out.append(f)
    elif state in ("fresh", "unmanaged"):
        f = Finding("bundle-not-installed", "AppBootstrapAI isn't installed (or has no manifest)",
                    "medium", None, None, "Preview, then apply: " + rec["command_str"])
        f.add("(repo root)")
        out.append(f)
    return status, out


# Deep reviews worth running even when no grep fires: the judgment-heavy areas.
BASELINE_SKILLS = {
    "apple": ["swiftui-pro", "swift-concurrency-pro", "swift-accessibility-pro", "swift-testing-pro"],
    "android": ["android-compose-pro", "android-coroutines-pro", "android-accessibility-pro"],
}
NEW_PROJECT_SKILLS = {
    "apple": ["swift-modularization-pro", "swift-design-system-pro"],
    "android": ["android-modularization-pro", "android-design-system-pro"],
}
# Libraries: API surface, manifest, and docs matter more than app scaffolding.
PACKAGE_SKILLS = {
    "apple": ["swift-package-pro", "swift-concurrency-pro", "swift-testing-pro", "swift-docc-pro"],
    "android": ["android-gradle-architecture-pro", "android-coroutines-pro", "r8-shrink-pro"],
}


def project_kind(target: str) -> str:
    """'package' for a library (Swift package or Android library), else 'app'."""
    def found(pattern):
        return any(not (set(p.split(os.sep)) & recommend.SKIP_DIRS)
                   for p in glob.glob(os.path.join(target, "**", pattern), recursive=True))

    if found("*.xcodeproj") or found("*.xcworkspace"):
        return "app"
    scripts = " ".join(_read(p) for pat in ("build.gradle", "build.gradle.kts")
                       for p in glob.glob(os.path.join(target, "**", pat), recursive=True)
                       if not (set(p.split(os.sep)) & recommend.SKIP_DIRS))
    if re.search(r"com\.android\.application|android\.application\b|\bapplicationId\b", scripts):
        return "app"
    if os.path.isfile(os.path.join(target, "Package.swift")):
        return "package"
    if re.search(r"com\.android\.library|android\.library\b", scripts):
        return "package"
    return "app"


def load_baseline(path):
    """Return {(id, file): {"count": n, "reason": str}} from a baseline file."""
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {}
    out = {}
    for e in data.get("entries", []):
        if e.get("id") and e.get("file") is not None:
            out[(e["id"], e["file"])] = {"count": int(e.get("count", 1)),
                                         "reason": e.get("reason", "")}
    return out


def apply_baseline(ordered, baseline):
    """Subtract accepted counts per (id, file). Returns (active, baselined, stale)."""
    active, accepted, used = [], [], set()
    for f in ordered:
        if f.id in UNBASELINABLE or not baseline:
            active.append(f)
            continue
        new_locs, suppressed = [], 0
        per_file = _per_file(f)
        for file, cur in per_file.items():
            entry = baseline.get((f.id, file))
            if entry:
                used.add((f.id, file))
            allowed = min(cur, entry["count"]) if entry else 0
            suppressed += allowed
            if cur > allowed:
                # Lines move, so a file over its count reports all its locations.
                new_locs += [loc for loc in f.all_locations if _loc_file(loc) == file]
        if suppressed:
            accepted.append({"id": f.id, "severity": f.severity, "title": f.title,
                             "count": suppressed})
        if new_locs:
            f.baselined = suppressed
            f.count -= suppressed
            f.all_locations = new_locs
            f.locations = new_locs[:MAX_LOCATIONS]
            active.append(f)
    stale = [{"id": k[0], "file": k[1]} for k in baseline if k not in used]
    return active, accepted, stale


def write_baseline(path, ordered, previous, reason):
    entries = []
    for f in ordered:
        if f.id in UNBASELINABLE:
            continue
        for file, count in sorted(_per_file(f).items()):
            prior = previous.get((f.id, file), {}).get("reason", "")
            entries.append({"id": f.id, "file": file, "count": count,
                            "reason": prior or reason})
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as fh:
        json.dump({"schema_version": 1,
                   "note": "Accepted AppBootstrapAI audit findings. Give every entry a reason; "
                           "delete entries as you fix them.",
                   "entries": entries}, fh, indent=2)
        fh.write("\n")
    return entries


def build(target, bundle, bundle_commit, recommended, all_cats,
          baseline_path=None, write_baseline_reason=None, install_check=True,
          steering_only=False):
    target = os.path.abspath(target)
    rec = recommend.build(target, recommended, all_cats, os.path.join(bundle, "install.sh"))
    platform = rec["platform"] or ""
    platforms = {"apple", "android"} if platform in ("both", "") else {platform}
    kind = project_kind(target) if os.path.isdir(target) else "app"

    findings: dict = {}
    scan = os.path.isdir(target) and not steering_only
    facts = scan_sources(target, platforms, findings) if scan else {"source_files": 0}
    if scan:
        # Project-shape checks need to know the platform; skip them when it's unknown.
        _structural(target, platforms if platform else set(), facts, findings, kind)
    steering_summary = None
    if os.path.isdir(target):
        s_findings, steering_summary = steering.run(
            target, bundle, platforms if platform else set(), _manifest_files(target), SECRET_PATTERN)
        for sf in s_findings:
            f = Finding(sf["id"], sf["title"], sf["severity"], sf["rule"], None, sf["fix"])
            for loc in sf["locations"]:
                f.add(loc)
            findings[f.id] = f
    status, bundle_findings = bundle_status(target, rec, bundle_commit)
    if not install_check or steering_only:
        bundle_findings = []

    installed_paths = _installed_paths(target)
    ordered = bundle_findings + sorted(findings.values(),
                                       key=lambda f: (SEV_RANK[f.severity], -f.count, f.id))
    mode = "steering" if steering_only else ("new" if facts["source_files"] < 10 else "existing")

    baseline_info = None
    if baseline_path:
        previous = load_baseline(baseline_path)
        if write_baseline_reason is not None:
            entries = write_baseline(baseline_path, ordered, previous, write_baseline_reason)
            previous = load_baseline(baseline_path)
            baseline_info = {"written": True, "entries_written": len(entries)}
        ordered, accepted, stale = apply_baseline(ordered, previous)
        if previous or baseline_info:
            baseline_info = dict(baseline_info or {}, **{
                "path": baseline_path,
                "entries": len(previous),
                "missing_reason": sum(1 for e in previous.values() if not e["reason"].strip()),
                "suppressed": accepted,
                "stale": stale,
            })

    checks = [_finding_json(f, bundle, installed_paths) for f in ordered]
    skills = [] if steering_only else _skill_plan(ordered, platforms, mode, kind, bundle)
    summary = {s: sum(1 for f in ordered if f.severity == s) for s in SEVERITIES}

    return {
        "target": target,
        "bundle": bundle,
        "mode": mode,
        "kind": kind,
        "platform": platform or None,
        "source_files": facts["source_files"],
        "install": status,
        "summary": summary,
        "findings": checks,
        "skills_to_run": skills,
        "steering": steering_summary,
        "baseline": baseline_info,
        "playbook": os.path.join(bundle, "playbooks",
                                 "sync-and-audit.md" if install_check else "audit.md"),
    }


def _manifest_files(target):
    try:
        with open(os.path.join(target, ".claude", ".appbootstrap-manifest.json")) as fh:
            return [e for e in json.load(fh).get("files", []) if isinstance(e, dict)]
    except (OSError, ValueError):
        return []


def _installed_paths(target):
    return [e.get("path", "") for e in _manifest_files(target)]


def _finding_json(f: Finding, bundle, installed_paths):
    d = {"id": f.id, "severity": f.severity, "title": f.title, "count": f.count,
         "locations": f.locations, "fix": f.fix, "rule": f.rule, "skill": f.skill,
         "baselined": f.baselined}
    if f.rule:
        stem = os.path.splitext(f.rule)[0]
        d["rule_path"] = os.path.join(bundle, ".claude", "rules", f.rule)
        d["rule_installed"] = any(stem in p for p in installed_paths)
    if f.skill:
        d["skill_path"] = os.path.join(bundle, ".claude", "skills", f.skill, "SKILL.md")
    return d


def _skill_plan(ordered, platforms, mode, kind, bundle):
    plan, seen = [], set()

    def add(name, reason, files):
        path = os.path.join(bundle, ".claude", "skills", name, "SKILL.md")
        if name in seen or not os.path.isfile(path):
            return
        seen.add(name)
        plan.append({"skill": name, "skill_path": path, "reason": reason, "files": files})

    for f in ordered:
        if f.skill:
            add(f.skill, f"{f.severity}: {f.title}", f.locations)
    if kind == "package":
        extra, label = PACKAGE_SKILLS, "baseline deep review (library)"
    elif mode == "new":
        extra, label = NEW_PROJECT_SKILLS, "set up the foundation (new project)"
    else:
        extra, label = BASELINE_SKILLS, "baseline deep review"
    for p in sorted(platforms):
        for name in extra.get(p, []):
            add(name, label, [])
    if platforms == {"apple", "android"}:
        add("cross-platform-parity-pro", "two platforms: check drift", [])
    return plan


def render_human(r) -> str:
    out = [f"==> AppBootstrapAI audit — {r['target']}",
           f"    mode:      {r['mode']} ({r['source_files']} source files), {r['kind']}",
           f"    platform:  {r['platform'] or 'unknown'}",
           f"    install:   {r['install']['state']}"
           + ("" if r["install"]["up_to_date"] is None
              else ("  (up to date)" if r["install"]["up_to_date"] else "  (upgrade available)")),
           "    findings:  " + ", ".join(f"{r['summary'][s]} {s}" for s in SEVERITIES), ""]
    for f in r["findings"]:
        tag = f"[{f['severity']}]"
        extra = f" new (+{f['baselined']} in baseline)" if f.get("baselined") else ""
        out.append(f"  {tag:<9}{f['title']}  ×{f['count']}{extra}")
        for loc in f["locations"]:
            out.append(f"             {loc}")
        if f["count"] + f.get("baselined", 0) > len(f["locations"]) and not f.get("baselined"):
            out.append(f"             … {f['count'] - len(f['locations'])} more")
        ref = " · ".join(x for x in (f.get("rule"), f.get("skill")) if x)
        out.append(f"             fix: {f['fix']}" + (f"  ({ref})" if ref else ""))
    b = r.get("baseline")
    if b:
        if b.get("written"):
            out += ["", f"  Wrote {b['entries_written']} baseline entries to {b['path']}."]
        hidden = sum(a["count"] for a in b["suppressed"])
        out += ["", f"  Baseline: {b['entries']} entries, {hidden} accepted occurrence(s) hidden"
                    f" ({b['path']})"]
        if b["missing_reason"]:
            out.append(f"    {b['missing_reason']} entr{'y has' if b['missing_reason'] == 1 else 'ies have'}"
                       " no reason: add one, or fix the code and delete the entry.")
        if b["stale"]:
            out.append(f"    {len(b['stale'])} entr{'y is' if len(b['stale']) == 1 else 'ies are'}"
                       " fixed: re-run with --write-baseline to drop them.")
    st = r.get("steering")
    if st:
        own = [f for f in st["files"] if f["owner"] == "project" and f["kind"] != "config"]
        cost = ", ".join(f"{a} ~{t}" for a, t in sorted(st["always_loaded_tokens_est"].items()))
        out += ["", f"  AI steering: {st['project_files']} project file(s), {st['bundle_files']} from the bundle;"
                    f" agents: {', '.join(st['agents']) or 'none'}",
                f"    always-loaded tokens per agent (est.): {cost or 'none'}"]
        for f in own[:12]:
            out.append(f"    - {f['path']:<44} {f['agent']:<10} {f['kind']:<10} {f['lines']} lines")
        if len(own) > 12:
            out.append(f"    … {len(own) - 12} more")
        out.append(f"    review guide: {st['rule_path']}")
    if r["skills_to_run"]:
        out += ["", "  Deep reviews to run (load each SKILL.md and review the listed files):"]
        for s in r["skills_to_run"]:
            out.append(f"    - {s['skill']:<28} {s['reason']}")
    out += ["", f"  Agent workflow: {r['playbook']}"]
    return "\n".join(out)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Audit a repo against the AppBootstrapAI bundle.")
    ap.add_argument("--target", default=".")
    ap.add_argument("--bundle", required=True)
    ap.add_argument("--bundle-commit", default="unknown")
    ap.add_argument("--recommended", default="")
    ap.add_argument("--all", default="")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--fail-on", choices=SEVERITIES)
    ap.add_argument("--baseline", help=f"baseline file (default: <target>/{DEFAULT_BASELINE})")
    ap.add_argument("--no-baseline", action="store_true", help="report every finding")
    ap.add_argument("--write-baseline", action="store_true",
                    help="accept all current findings into the baseline")
    ap.add_argument("--baseline-reason", default="",
                    help="reason recorded on new baseline entries")
    ap.add_argument("--no-install-check", action="store_true",
                    help="skip the bundle install-state findings (audit without adopting)")
    ap.add_argument("--steering-only", action="store_true",
                    help="check only the repo's AI steering files, not its code")
    args = ap.parse_args(argv)

    if not os.path.isdir(args.target):
        print(f"error: target directory does not exist: {args.target}", file=sys.stderr)
        return 1
    baseline_path = None
    if not args.no_baseline:
        baseline_path = os.path.abspath(args.baseline or os.path.join(args.target, DEFAULT_BASELINE))
    r = build(args.target, os.path.abspath(args.bundle), args.bundle_commit,
              args.recommended.split(), args.all.split(), baseline_path,
              args.baseline_reason if args.write_baseline else None,
              install_check=not args.no_install_check, steering_only=args.steering_only)
    print(json.dumps(r, indent=2) if args.json else render_human(r))
    if args.fail_on:
        limit = SEV_RANK[args.fail_on]
        if any(SEV_RANK[f["severity"]] <= limit for f in r["findings"]):
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
