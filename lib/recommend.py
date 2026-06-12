#!/usr/bin/env python3
"""AppBootstrapAI installer — `recommend` action.

Analyze a target directory and emit the recommended AppBootstrapAI command
(create / adopt / upgrade) plus the reasoning behind every choice. The point is
to let an AI agent (or a human) point at a repo and get the *exact* command to
run in a single call, instead of grepping the tree by hand.

Invoked by install.sh's `recommend` verb:

    python3 lib/recommend.py --target DIR \\
        --recommended "<space-separated recommended categories>" \\
        --all "<space-separated all categories>" \\
        --self /abs/path/to/install.sh [--json]

Stdout is either a human-readable report or, with --json, a single JSON object.
Detection mirrors lib/detect_platform.sh for platform signals; the framework →
feature-category mapping is unique to this module. It only reads the tree; it
never writes.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys

# Directories that never contain meaningful source for detection — skip them so
# a huge repo's build output / dependencies don't slow the scan or trip false
# positives.
SKIP_DIRS = {
    ".git", ".build", "build", ".gradle", "DerivedData", "Pods", "Carthage",
    "node_modules", ".swiftpm", ".idea", "xcuserdata", ".cxx", "captures",
}

# Only read file contents for these extensions when scanning for imports.
TEXT_EXTS = {".swift", ".kt", ".kts", ".gradle", ".yml", ".yaml", ".rb"}
MAX_READ_BYTES = 2_000_000  # skip absurdly large files

# Which opt-in categories are meaningful per platform. Recommended categories
# install regardless; these are the extras `recommend` may suggest on top.
APPLE_OPT_INS = {"ai", "spatial", "persistence", "deployment"}
ANDROID_OPT_INS = {"ai", "migration", "shrinking", "persistence", "deployment"}


def detect_state(target: str) -> str:
    """managed | unmanaged | fresh | missing."""
    if not os.path.isdir(target):
        return "missing"
    if os.path.isfile(os.path.join(target, ".claude", ".appbootstrap-manifest.json")):
        return "managed"
    if os.path.isdir(os.path.join(target, ".claude", "rules")):
        return "unmanaged"  # .claude/rules present but no manifest (pre-manifest install)
    return "fresh"


def detect_platform(target: str):
    """Return (platform, apple_signals, android_signals). Mirrors lib/detect_platform.sh."""
    apple, android = [], []
    if os.path.isdir(target):
        if os.path.isfile(os.path.join(target, "Package.swift")):
            apple.append("Package.swift")
        for p in sorted(glob.glob(os.path.join(target, "*.xcodeproj"))
                        + glob.glob(os.path.join(target, "*.xcworkspace"))):
            apple.append(os.path.basename(p))
        for f in ("build.gradle", "build.gradle.kts", "settings.gradle",
                  "settings.gradle.kts", "gradlew"):
            if os.path.isfile(os.path.join(target, f)):
                android.append(f)
    if apple and android:
        platform = "both"
    elif apple:
        platform = "apple"
    elif android:
        platform = "android"
    else:
        platform = ""
    return platform, apple, android


def scan_tree(target: str):
    """Single walk of the tree collecting language presence + feature signals.

    Returns (langs, reasons) where langs is a set of {"swift","kotlin","objc"}
    and reasons maps category -> sorted list of human reasons.
    """
    langs = set()
    reasons: dict[str, set] = {}

    def add(cat: str, why: str) -> None:
        reasons.setdefault(cat, set()).add(why)

    if not os.path.isdir(target):
        return langs, {}

    for root, dirs, files in os.walk(target):
        # Prune skip dirs + Xcode project bundles (but keep .xcdatamodeld / .rkassets,
        # which we want to *detect* as signals below).
        kept = []
        for d in dirs:
            if d in SKIP_DIRS or d.endswith((".xcodeproj", ".xcworkspace")):
                continue
            if d.endswith(".xcdatamodeld"):
                add("persistence", "Core Data model (.xcdatamodeld)")
            if d.endswith(".rkassets"):
                add("spatial", "Reality Composer Pro assets (.rkassets)")
            kept.append(d)
        dirs[:] = kept

        rel = os.path.relpath(root, target).replace(os.sep, "/")
        for fn in files:
            ext = os.path.splitext(fn)[1].lower()
            path = os.path.join(root, fn)

            # Filename / path signals (no read needed).
            if fn == "Fastfile":
                add("deployment", "Fastfile")
            elif fn == "ExportOptions.plist":
                add("deployment", "ExportOptions.plist")
            elif fn in ("proguard-rules.pro", "consumer-rules.pro"):
                add("shrinking", fn)
            if ext == ".usdz":
                add("spatial", "USDZ 3D asset")
            if ext in (".m", ".mm"):
                langs.add("objc")
            elif ext == ".swift":
                langs.add("swift")
            elif ext in (".kt", ".kts"):
                langs.add("kotlin")
            # Android XML layouts → XML→Compose migration is relevant.
            if ext == ".xml" and ("/res/layout" in (rel + "/" + fn) or rel.endswith("/res/layout")
                                  or "/res/layout/" in (rel + "/")):
                add("migration", "XML layout under res/layout/")

            # Content scans for the import/usage signals.
            if ext in TEXT_EXTS:
                try:
                    if os.path.getsize(path) > MAX_READ_BYTES:
                        continue
                    with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                        text = fh.read()
                except OSError:
                    continue
                _scan_text(ext, text, add)

    # Normalize to sorted lists.
    return langs, {k: sorted(v) for k, v in reasons.items()}


def _scan_text(ext: str, text: str, add) -> None:
    """Apply per-extension content heuristics."""
    if ext == ".swift":
        if "import FoundationModels" in text:
            add("ai", "import FoundationModels")
        if ("import CoreData" in text or "NSManagedObject" in text
                or "NSPersistentContainer" in text or "NSPersistentCloudKitContainer" in text):
            add("persistence", "Core Data API usage")
        if "import SwiftData" in text or "@Model" in text:
            add("persistence", "SwiftData (@Model)")
        if ("import RealityKit" in text or "RealityKitContent" in text
                or "ImmersiveSpace" in text or ".immersionStyle" in text):
            add("spatial", "RealityKit / ImmersiveSpace")
    elif ext in (".kt", ".kts"):
        if "androidx.room" in text or "RoomDatabase" in text or "@Dao" in text or "@Entity" in text:
            add("persistence", "Room database")
        if ": Fragment(" in text or "extends Fragment" in text or "androidx.fragment" in text:
            add("migration", "Fragment / legacy View usage")
        if ("com.google.mlkit.genai" in text or "com.google.firebase.ai" in text
                or "GenerativeModel" in text or "generateContentStream" in text):
            add("ai", "Gemini / ML Kit GenAI / Firebase AI usage")
    if ext in (".gradle", ".kts"):
        if "isMinifyEnabled = true" in text or "minifyEnabled true" in text:
            add("shrinking", "R8/ProGuard (minify enabled)")
        if "com.github.triplet.play" in text or "bundleRelease" in text:
            add("deployment", "Play publishing (Gradle)")
        if "androidx.room" in text:
            add("persistence", "Room dependency")
    if ext in (".yml", ".yaml", ".rb"):
        low = text.lower()
        if any(s in low for s in ("upload_to_testflight", "altool", "xcodebuild archive", "fastlane")):
            add("deployment", "CI / fastlane (Apple shipping)")
        if any(s in low for s in ("bundlerelease", "upload_to_play_store", "supply", "gradle-play-publisher")):
            add("deployment", "CI (Play shipping)")


def detect_agents(target: str):
    """Existing agent footprints in the target → list of agent tokens (claude first)."""
    found = []
    if os.path.isdir(os.path.join(target, ".claude")):
        found.append("claude")
    if os.path.isfile(os.path.join(target, ".github", "copilot-instructions.md")):
        found.append("copilot")
    if os.path.isdir(os.path.join(target, ".cursor", "rules")):
        found.append("cursor")
    if os.path.isfile(os.path.join(target, "GEMINI.md")):
        found.append("gemini")
    if os.path.isfile(os.path.join(target, "AGENTS.md")):
        found.append("codex")
    if os.path.isdir(os.path.join(target, ".kiro", "steering")):
        found.append("kiro")
    return found


def read_manifest_selection(target: str):
    """Return the manifest's selection dict, or None."""
    path = os.path.join(target, ".claude", ".appbootstrap-manifest.json")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh).get("selection")
    except (OSError, ValueError):
        return None


def order_by(cats, ref):
    """Return cats ordered by their position in ref (stable, ref-driven)."""
    return [c for c in ref if c in set(cats)]


def build(target, recommended, all_cats, self_cmd):
    state = detect_state(target)
    platform, apple_sig, android_sig = detect_platform(target)
    langs, reasons = scan_tree(target)

    # Which opt-in categories apply for this platform.
    if platform == "apple":
        allowed = APPLE_OPT_INS
    elif platform == "android":
        allowed = ANDROID_OPT_INS
    elif platform == "both":
        allowed = APPLE_OPT_INS | ANDROID_OPT_INS
    else:
        allowed = APPLE_OPT_INS | ANDROID_OPT_INS  # unknown platform — don't pre-filter

    all_set = set(all_cats)
    detected_extras = order_by(
        [c for c in reasons if c in allowed and c in all_set and c not in recommended],
        all_cats,
    )
    feature_reasons = {c: reasons[c] for c in detected_extras}

    # Apple language: only meaningful when apple is in scope.
    apple_language = None
    if platform in ("apple", "both", ""):
        if "objc" in langs and "swift" in langs:
            apple_language = "both"
        elif "objc" in langs:
            apple_language = "objc"
        elif "swift" in langs:
            apple_language = "swift"
        elif platform in ("apple", "both"):
            apple_language = "swift"  # apple project, no sources scanned yet → default

    notes = []

    # Existing-agent footprint (suggest installing for what's already there).
    detected_agents = detect_agents(target)

    manifest_sel = read_manifest_selection(target) if state == "managed" else None

    # ---- assemble action + command ------------------------------------------
    features_extras = list(detected_extras)
    if state == "managed" and manifest_sel:
        platform = manifest_sel.get("platform") or platform
        apple_language = manifest_sel.get("apple_language") or apple_language
        installed_resolved = set(manifest_sel.get("features_resolved") or [])
        # Categories newly detected in the source but not yet installed.
        new_categories = [c for c in detected_extras if c not in installed_resolved]
        agents = manifest_sel.get("agents_input") or "claude"
        if new_categories:
            # Suggest an upgrade that adds them on top of the existing selection.
            base = manifest_sel.get("features_input") or "recommended"
            feat_input = base + "," + ",".join(new_categories)
            action = "upgrade (add newly-detected categories)"
            cmd = [self_cmd, "upgrade", target, "--features", feat_input, "--apply"]
            notes.append("newly detected since install: " + ", ".join(new_categories))
        else:
            action = "upgrade"
            feat_input = manifest_sel.get("features_input") or "recommended"
            cmd = [self_cmd, "upgrade", target, "--apply"]
        preview = [self_cmd, "upgrade", target]  # plan-only
    else:
        agents = ",".join(detected_agents) if detected_agents else "claude"
        if "claude" not in agents.split(","):
            agents = "claude," + agents
        feat_input = "recommended" + ("," + ",".join(features_extras) if features_extras else "")
        plat_for_cmd = platform or "both"
        if not platform:
            notes.append("no platform signals found — set --platform apple|android|both explicitly")
        cmd = [self_cmd, "install", target, "--platform", plat_for_cmd]
        if plat_for_cmd in ("apple", "both") and apple_language:
            cmd += ["--apple-language", apple_language]
        cmd += ["--features", feat_input]
        if agents != "claude":
            cmd += ["--agents", agents]
        if state == "missing":
            cmd.append("--new")
            action = "create (new project)"
            notes.append("--new makes the dir + git init; it does not generate an Xcode/Gradle project")
        elif state == "unmanaged":
            action = "adopt (refresh existing files; adds a manifest → upgrade-able afterward)"
        else:
            action = "adopt (fresh)"
        preview = cmd + ["--dry-run"]

    return {
        "target": os.path.abspath(target),
        "state": state,
        "platform": platform or None,
        "platform_signals": {"apple": apple_sig, "android": android_sig},
        "apple_language": apple_language,
        "features": feat_input,
        "features_detected_extras": features_extras,
        "feature_reasons": {k: sorted(v) for k, v in feature_reasons.items()},
        "agents": agents,
        "action": action,
        "notes": notes,
        "command": cmd,
        "command_str": " ".join(cmd),
        "preview_command": preview,
        "preview_command_str": " ".join(preview),
    }


def render_human(r) -> str:
    out = []
    out.append(f"==> AppBootstrapAI recommendation — {r['target']}")
    out.append(f"    state:     {r['state']}")
    sig = r["platform_signals"]
    sig_str = ", ".join(sig["apple"] + sig["android"]) or "none"
    out.append(f"    platform:  {r['platform'] or 'unknown'}  (signals: {sig_str})")
    if r["apple_language"]:
        out.append(f"    language:  {r['apple_language']}")
    out.append(f"    features:  {r['features']}")
    for cat in r["features_detected_extras"]:
        why = "; ".join(r["feature_reasons"].get(cat, []))
        out.append(f"                 + {cat:<12} ← {why}")
    out.append(f"    agents:    {r['agents']}")
    out.append(f"    action:    {r['action']}")
    for n in r["notes"]:
        out.append(f"    note:      {n}")
    out.append("")
    out.append("  Run this:")
    out.append(f"    {r['command_str']}")
    out.append("")
    out.append("  Preview first (writes nothing):")
    out.append(f"    {r['preview_command_str']}")
    return "\n".join(out)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Recommend an AppBootstrapAI command for a directory.")
    ap.add_argument("--target", default=".")
    ap.add_argument("--recommended", default="")
    ap.add_argument("--all", default="")
    ap.add_argument("--self", dest="self_cmd", default="install.sh")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    r = build(
        args.target,
        args.recommended.split(),
        args.all.split(),
        args.self_cmd,
    )
    if args.json:
        print(json.dumps(r, indent=2))
    else:
        print(render_human(r))
    return 0


if __name__ == "__main__":
    sys.exit(main())
