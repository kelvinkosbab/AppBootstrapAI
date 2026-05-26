# shellcheck shell=bash
# AppBootstrapAI installer — platform auto-detection.
#
# Sourced from install.sh. Provides:
#   detect_platform(target_dir)    → sets DETECTED_PLATFORM + DETECTED_APPLE_SIGNALS
#                                    + DETECTED_ANDROID_SIGNALS globals as side effects
#                                    (subshell-safe via globals, not stdout — see
#                                    earlier bug fix in commit 38660f9)
#
# Also runs the autodetect block itself: if $PLATFORM is empty after arg parsing,
# call detect_platform() and either populate $PLATFORM from the result or fall
# back to "both" with PLATFORM_AUTODETECT_FALLBACK=true.

# --- Platform auto-detection --------------------------------------------------
#
# When --platform isn't explicitly set, look at the TARGET directory for
# canonical project files and pick the dominant platform. Falls back to "both"
# if nothing matches (fresh / empty repo). An explicit --platform always wins.
#
# Signals checked:
#   Apple:   Package.swift, *.xcodeproj/, *.xcworkspace/
#   Android: build.gradle{,.kts}, settings.gradle{,.kts}, gradlew

# Globals populated by detect_platform. Set as side effects of calling the
# function (not via command substitution, because subshell assignments don't
# propagate). Read these after the call.
#   DETECTED_PLATFORM         — "apple" | "android" | "both" | "" (no signals)
#   DETECTED_APPLE_SIGNALS    — space-separated filenames that matched
#   DETECTED_ANDROID_SIGNALS  — same, for Android
DETECTED_PLATFORM=""
DETECTED_APPLE_SIGNALS=""
DETECTED_ANDROID_SIGNALS=""

detect_platform() {
    local target="$1"
    local apple=""
    local android=""

    # Apple signals.
    [[ -f "$target/Package.swift" ]] && apple="$apple Package.swift"

    # Glob expansion for *.xcodeproj / *.xcworkspace. nullglob makes the loop
    # skip cleanly when nothing matches; basename trims the path back to the
    # bare filename for printing.
    shopt -s nullglob
    local match
    for match in "$target"/*.xcodeproj "$target"/*.xcworkspace; do
        apple="$apple $(basename "$match")"
    done

    # Android signals.
    [[ -f "$target/build.gradle"      ]] && android="$android build.gradle"
    [[ -f "$target/build.gradle.kts"  ]] && android="$android build.gradle.kts"
    [[ -f "$target/settings.gradle"   ]] && android="$android settings.gradle"
    [[ -f "$target/settings.gradle.kts" ]] && android="$android settings.gradle.kts"
    [[ -f "$target/gradlew"           ]] && android="$android gradlew"

    DETECTED_APPLE_SIGNALS="${apple# }"
    DETECTED_ANDROID_SIGNALS="${android# }"

    if [[ -n "$DETECTED_APPLE_SIGNALS" && -n "$DETECTED_ANDROID_SIGNALS" ]]; then
        DETECTED_PLATFORM="both"
    elif [[ -n "$DETECTED_APPLE_SIGNALS" ]]; then
        DETECTED_PLATFORM="apple"
    elif [[ -n "$DETECTED_ANDROID_SIGNALS" ]]; then
        DETECTED_PLATFORM="android"
    else
        DETECTED_PLATFORM=""
    fi
}

# Auto-detect if PLATFORM wasn't set explicitly on the command line. Two
# outcomes:
#   - detection finds signals → use them, flag PLATFORM_AUTODETECTED for the header
#   - detection finds nothing → fall back to "both", flag PLATFORM_AUTODETECT_FALLBACK
# shellcheck disable=SC2034   # both are read by lib/install_mode.sh's header echo
PLATFORM_AUTODETECTED="false"
# shellcheck disable=SC2034
PLATFORM_AUTODETECT_FALLBACK="false"
if [[ -z "$PLATFORM" ]]; then
    # Resolve target to an absolute path for detection. Don't error here on a
    # missing dir — the install path below produces a better error message.
    if [[ -d "$TARGET" ]]; then
        detect_target="$(cd "$TARGET" && pwd)"
    else
        detect_target="$TARGET"
    fi
    detect_platform "$detect_target"
    if [[ -n "$DETECTED_PLATFORM" ]]; then
        PLATFORM="$DETECTED_PLATFORM"
        # shellcheck disable=SC2034   # read by lib/install_mode.sh's header echo
        PLATFORM_AUTODETECTED="true"
    else
        PLATFORM="both"
        # shellcheck disable=SC2034   # read by lib/install_mode.sh's header echo
        PLATFORM_AUTODETECT_FALLBACK="true"
    fi
fi

case "$PLATFORM" in
    apple|android|both) ;;
    *)
        echo "error: --platform must be apple, android, or both (got: $PLATFORM)" >&2
        exit 1
        ;;
esac

case "$APPLE_LANG" in
    swift|objc|both) ;;
    *)
        echo "error: --apple-language must be swift, objc, or both (got: $APPLE_LANG)" >&2
        exit 1
        ;;
esac

if [[ "$JSON_OUTPUT" == "true" ]] && [[ "$ACTION" != "list" ]]; then
    echo "error: --json is only valid with --list" >&2
    exit 1
fi
