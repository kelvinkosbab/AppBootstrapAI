#!/usr/bin/env bash
# scaffold-spm-package.sh — create a KozBon-style local Swift package so an
# existing app can move its logic out of the .xcodeproj and into modules.
#
# Generates  <target>/<Name>/  with:
#   - Package.swift          a makeTargets()-based manifest (one block per module)
#   - <Module>/Sources/      a compiling placeholder per module (AppCore also gets
#                            a SwiftUI AppRootView for the app's @main to show)
#   - <Module>/Tests/        a passing Swift Testing placeholder per module
#   - .gitignore             .build/ .swiftpm/ .DS_Store
#
# A module named exactly "AppCore" becomes the umbrella: it depends on every
# other module in the list and is the only product, so the app target links
# AppCore and nothing else. Without AppCore, every module is a product. This
# mirrors KozBon's KozBonPackages layout.
#
# NON-DESTRUCTIVE: never overwrites an existing file. Refuses to scaffold into an
# existing package directory unless --force (and even then only fills in the
# files that are missing). It does NOT move your code — that's the incremental,
# per-module step you do by hand (see apple-modular-architecture.md).
#
# Usage:
#   scaffold-spm-package.sh [<target-dir>] [options]
#
#   <target-dir>            Repo to scaffold into (default: current directory).
#   --name <PackageName>    Package dir + name (default: <repo-basename>Packages).
#   --modules <csv>         Modules to create (default: Core,AppCore).
#   --tools-version <x.y>   swift-tools-version (default: 6.0; 6.2 with --main-actor).
#   --main-actor <csv|all>  Modules that default to @MainActor isolation
#                           (.defaultIsolation(MainActor.self), Swift 6.2+). "all"
#                           means every module except Core. Use it for UI and
#                           feature modules in an app; keep Core nonisolated.
#   --dry-run               Print the plan; write nothing.
#   --force                 Fill missing files in an existing package dir.
#   -h, --help              This help.
#
# Examples:
#   scaffold-spm-package.sh .                       # ./<repo>Packages with Core + AppCore
#   scaffold-spm-package.sh ~/Projects/MyApp --modules Core,Models,Storage,Feature,UI,AppCore
#   scaffold-spm-package.sh . --name MyAppKit --dry-run
#   scaffold-spm-package.sh . --modules Core,Feature,UI,AppCore --main-actor all

set -euo pipefail

# --- Defaults ----------------------------------------------------------------
TARGET="."
PKG_NAME=""
MODULES_CSV="Core,AppCore"
TOOLS_VERSION=""
MAIN_ACTOR_CSV=""
DRY_RUN=0
FORCE=0

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
note() { printf '\033[1m%s\033[0m\n' "$*"; }

# --- Arg parsing -------------------------------------------------------------
need_value() {  # need_value "$@" with the flag in $1
    [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || die "$1 needs a value (see --help)"
}
positional_seen=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)          need_value "$@"; PKG_NAME="$2"; shift 2 ;;
        --modules)       need_value "$@"; MODULES_CSV="$2"; shift 2 ;;
        --tools-version) need_value "$@"; TOOLS_VERSION="$2"; shift 2 ;;
        --main-actor)    need_value "$@"; MAIN_ACTOR_CSV="$2"; shift 2 ;;
        --dry-run)       DRY_RUN=1; shift ;;
        --force)         FORCE=1; shift ;;
        -h|--help)       usage 0 ;;
        -*)              die "unknown option: $1 (see --help)" ;;
        *)
            if [[ "$positional_seen" -eq 0 ]]; then
                TARGET="$1"; positional_seen=1; shift
            else
                die "unexpected argument: $1"
            fi
            ;;
    esac
done

# --- Resolve target + package name -------------------------------------------
[[ -d "$TARGET" ]] || die "target directory does not exist: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"

if [[ -z "$PKG_NAME" ]]; then
    PKG_NAME="$(basename "$TARGET")Packages"
fi
[[ "$PKG_NAME" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] \
    || die "invalid package name '$PKG_NAME' (must be a Swift identifier)"

# --- Parse + validate modules ------------------------------------------------
IFS=',' read -r -a MODULES <<< "$MODULES_CSV"

declare -a CLEAN_MODULES=()
for m in "${MODULES[@]}"; do
    m="${m// /}"
    [[ -n "$m" ]] || continue
    [[ "$m" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] \
        || die "invalid module name '$m' (must be a Swift identifier)"
    case "$m" in
        Swift|Foundation|SwiftUI|UIKit|AppKit|Combine|Observation|Testing|XCTest|Dispatch|os|OSLog|Darwin|Glibc|PackageDescription)
            die "module name '$m' clashes with a system module" ;;
    esac
    [[ "$m" == *Tests ]] && die "module name '$m' ends in 'Tests', which clashes with the generated test targets"
    for seen in "${CLEAN_MODULES[@]+"${CLEAN_MODULES[@]}"}"; do
        [[ "$seen" == "$m" ]] && die "module '$m' is listed twice"
    done
    CLEAN_MODULES+=("$m")
done
[[ "${#CLEAN_MODULES[@]}" -ge 1 ]] || die "need at least one module (--modules)"
MODULES=("${CLEAN_MODULES[@]}")

# Which modules default to MainActor isolation?
declare -a MAIN_ACTOR_MODULES=()
if [[ -n "$MAIN_ACTOR_CSV" ]]; then
    if [[ "$MAIN_ACTOR_CSV" == "all" ]]; then
        for m in "${MODULES[@]}"; do
            [[ "$m" != "Core" ]] && MAIN_ACTOR_MODULES+=("$m")
        done
    else
        IFS=',' read -r -a requested <<< "$MAIN_ACTOR_CSV"
        for r in "${requested[@]}"; do
            r="${r// /}"
            [[ -n "$r" ]] || continue
            [[ " ${MODULES[*]} " == *" $r "* ]] || die "--main-actor names '$r', which isn't in --modules"
            MAIN_ACTOR_MODULES+=("$r")
        done
    fi
fi
is_main_actor() {
    local m
    for m in "${MAIN_ACTOR_MODULES[@]+"${MAIN_ACTOR_MODULES[@]}"}"; do
        [[ "$m" == "$1" ]] && return 0
    done
    return 1
}

# .defaultIsolation needs tools 6.2; otherwise stay on the lowest useful version.
if [[ -z "$TOOLS_VERSION" ]]; then
    if [[ "${#MAIN_ACTOR_MODULES[@]}" -gt 0 ]]; then TOOLS_VERSION="6.2"; else TOOLS_VERSION="6.0"; fi
elif [[ "${#MAIN_ACTOR_MODULES[@]}" -gt 0 ]]; then
    awk -v v="$TOOLS_VERSION" 'BEGIN { split(v, a, "."); exit !((a[1] > 6) || (a[1] == 6 && a[2] >= 2)) }' \
        || die "--main-actor needs --tools-version 6.2 or later (got $TOOLS_VERSION)"
fi

# Does the list contain an AppCore umbrella?
HAS_UMBRELLA=0
for m in "${MODULES[@]}"; do
    [[ "$m" == "AppCore" ]] && HAS_UMBRELLA=1
done

PKG_DIR="$TARGET/$PKG_NAME"

# --- Pre-flight --------------------------------------------------------------
if [[ -e "$PKG_DIR" && "$FORCE" -ne 1 ]]; then
    die "package directory already exists: $PKG_DIR
       re-run with --force to fill in missing files (existing files are never overwritten)."
fi

note "Scaffolding Swift package"
printf '  package:  %s\n' "$PKG_NAME"
printf '  path:     %s\n' "$PKG_DIR"
printf '  modules:  %s\n' "${MODULES[*]}"
printf '  umbrella: %s\n' "$([[ "$HAS_UMBRELLA" -eq 1 ]] && echo "AppCore (links every other module; the app links this)" || echo "none (modules are independent — add an 'AppCore' module for an umbrella)")"
printf '  tools:    swift-tools-version %s\n' "$TOOLS_VERSION"
if [[ "${#MAIN_ACTOR_MODULES[@]}" -gt 0 ]]; then
    printf '  @MainActor by default: %s\n' "${MAIN_ACTOR_MODULES[*]}"
fi
[[ "$DRY_RUN" -eq 1 ]] && printf '  mode:     DRY RUN (no files written)\n'
echo ""

# --- File writers (dry-run aware, never-overwrite) ---------------------------
WROTE=0
SKIPPED=0

write_file() {  # write_file <path> <emit-fn> [args...]
    # Runs in the main shell (not a pipeline) so the WROTE/SKIPPED counters
    # accumulate. The emit-fn produces the file body on stdout.
    local path="$1"; shift
    if [[ -e "$path" ]]; then
        printf '  skip   %s (exists)\n' "${path#"$TARGET"/}"
        SKIPPED=$((SKIPPED + 1))
        return
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '  create %s\n' "${path#"$TARGET"/}"
        WROTE=$((WROTE + 1))
        return
    fi
    mkdir -p "$(dirname "$path")"
    "$@" > "$path"
    printf '  create %s\n' "${path#"$TARGET"/}"
    WROTE=$((WROTE + 1))
}

# --- Generate Package.swift --------------------------------------------------
emit_package_swift() {
    cat <<EOF
// swift-tools-version: ${TOOLS_VERSION}
//
// Generated by AppBootstrapAI scaffold-spm-package.sh. Edit freely — this file
// is yours now. makeTargets() matches templates/Package.template.swift; adding a
// module is one + makeTargets(...) block, plus a product only if something
// outside this package imports it directly.
// See apple-spm-package-conventions.md and apple-modular-architecture.md.

import PackageDescription

// MARK: - Shared Settings

/// Applied to every target — source and test — so modules can't drift onto
/// different language modes. Keep it short and uniform.
let sharedSwiftSettings: [SwiftSetting] = [
$(emit_shared_settings)
]$(emit_main_actor_settings)

// MARK: - Target Helper

/// Creates a source target at \`{name}/Sources\` and a test target at
/// \`{name}/Tests\`. \`hasResources: true\` ships \`Sources/Resources/\` via
/// \`.process\`; \`hasTests: false\` is only for resource-only modules. The test
/// target always depends on the module; \`testDependencies\` adds fixtures.
/// \`swiftSettings\` are appended to \`sharedSwiftSettings\` on both targets.
func makeTargets(
    name: String,
    dependencies: [Target.Dependency] = [],
    hasTests: Bool = true,
    hasResources: Bool = false,
    testDependencies: [Target.Dependency] = [],
    testResources: [Resource]? = nil,
    swiftSettings: [SwiftSetting] = [],
    plugins: [Target.PluginUsage]? = nil
) -> [Target] {
    var targets: [Target] = [
        .target(
            name: name,
            dependencies: dependencies,
            path: "\\(name)/Sources",
            resources: hasResources ? [.process("Resources")] : nil,
            swiftSettings: sharedSwiftSettings + swiftSettings,
            plugins: plugins
        )
    ]
    if hasTests {
        targets.append(
            .testTarget(
                name: "\\(name)Tests",
                dependencies: [.byName(name: name)] + testDependencies,
                path: "\\(name)/Tests",
                resources: testResources,
                swiftSettings: sharedSwiftSettings + swiftSettings
            )
        )
    }
    return targets
}

// MARK: - Package

let package = Package(
    name: "${PKG_NAME}",
    platforms: [
        // Pick minimums you actually support.
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
$(emit_products)
    ],
    targets:
$(emit_targets)
)
EOF
}

emit_shared_settings() {
    if [[ "${#MAIN_ACTOR_MODULES[@]}" -gt 0 ]]; then
        cat <<'EOF'
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("InternalImportsByDefault"),
    // Swift 6.2 approachable concurrency: nonisolated async functions run on
    // the caller's actor, and conformances infer the conforming type's isolation.
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances")
EOF
    else
        cat <<'EOF'
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("InternalImportsByDefault")
EOF
    fi
}

emit_main_actor_settings() {
    [[ "${#MAIN_ACTOR_MODULES[@]}" -gt 0 ]] || return 0
    printf '\n\n'
    cat <<'EOF'
/// UI and feature modules default to @MainActor (SE-0466), so views and view
/// models need no per-type annotation. Core stays nonisolated; mark background
/// work `nonisolated` or `@concurrent` explicitly.
let mainActorByDefault: [SwiftSetting] = [
    .defaultIsolation(MainActor.self)
]
EOF
}

# With an AppCore umbrella the app links only AppCore, so the other modules stay
# out of products (apple-spm-package-conventions.md). Without one, every module
# is a product.
emit_products() {
    local i name line
    local -a products=()
    if [[ "$HAS_UMBRELLA" -eq 1 ]]; then
        products=("AppCore")
    else
        products=("${MODULES[@]}")
    fi
    for i in "${!products[@]}"; do
        name="${products[$i]}"
        line="        .library(name: \"$name\", targets: [\"$name\"])"
        [[ "$i" -lt $(( ${#products[@]} - 1 )) ]] && line="${line},"
        printf '%s\n' "$line"
    done
}

emit_targets() {
    local i name prefix settings
    for i in "${!MODULES[@]}"; do
        name="${MODULES[$i]}"
        prefix="        "
        [[ "$i" -gt 0 ]] && prefix="        + "
        settings=""
        if is_main_actor "$name"; then settings="mainActorByDefault"; fi
        if [[ "$name" == "AppCore" && "$HAS_UMBRELLA" -eq 1 && "${#MODULES[@]}" -gt 1 ]]; then
            # Umbrella: depends on every other module, in declared order.
            printf '%smakeTargets(\n' "$prefix"
            printf '            name: "AppCore",\n'
            printf '            dependencies: [\n'
            local j other first=1
            for j in "${!MODULES[@]}"; do
                other="${MODULES[$j]}"
                [[ "$other" == "AppCore" ]] && continue
                if [[ "$first" -eq 1 ]]; then first=0; else printf ',\n'; fi
                printf '                "%s"' "$other"
            done
            if [[ -n "$settings" ]]; then
                printf '\n            ],\n'
                printf '            swiftSettings: %s\n' "$settings"
            else
                printf '\n            ]\n'
            fi
            printf '        )\n'
        elif [[ -n "$settings" ]]; then
            printf '%smakeTargets(name: "%s", swiftSettings: %s)\n' "$prefix" "$name" "$settings"
        else
            printf '%smakeTargets(name: "%s")\n' "$prefix" "$name"
        fi
    done
}

# --- Generate per-module sources + tests -------------------------------------
emit_source() {  # $1 = module
    if [[ "$1" == "AppCore" && "$HAS_UMBRELLA" -eq 1 ]]; then
        emit_appcore_source
        return
    fi
    # The placeholder's name differs from the module's on purpose: a type named
    # like its module makes `Core.Foo` resolve to the type, which breaks
    # module-qualified lookups and .swiftinterface generation.
    cat <<EOF
// ${1} — replace this placeholder with the module's real public API.

/// Placeholder so the module compiles before real code lands. Delete it once
/// ${1} exposes real public API.
public enum ${1}Placeholder {
    public static let moduleName = "${1}"
}
EOF
}

emit_appcore_source() {
    cat <<'EOF'
// AppCore — the umbrella module the app target links. The app's @main shows
// AppRootView and does nothing else; routing and app-level wiring live here.

#if canImport(SwiftUI)
public import SwiftUI
#endif

/// Placeholder so the module compiles before real code lands.
public enum AppCorePlaceholder {
    public static let moduleName = "AppCore"
}

#if canImport(SwiftUI)
/// The app's root view. In the app target:
///
/// ```swift
/// import AppCore
/// import SwiftUI
///
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         WindowGroup { AppRootView() }
///     }
/// }
/// ```
public struct AppRootView: View {
    public init() {}

    public var body: some View {
        Text(verbatim: AppCorePlaceholder.moduleName)
    }
}
#endif
EOF
}

emit_test() {  # $1 = module
    cat <<EOF
import Testing
@testable import ${1}

@Suite("${1}")
struct ${1}Tests {
    @Test func placeholderIsWired() {
        #expect(${1}Placeholder.moduleName == "${1}")
    }
}
EOF
}

emit_gitignore() {
    cat <<'EOF'
.build/
.swiftpm/
.DS_Store
EOF
}

# --- Write everything --------------------------------------------------------
write_file "$PKG_DIR/Package.swift" emit_package_swift
write_file "$PKG_DIR/.gitignore"    emit_gitignore

for m in "${MODULES[@]}"; do
    write_file "$PKG_DIR/$m/Sources/$m.swift"        emit_source "$m"
    write_file "$PKG_DIR/$m/Tests/${m}Tests.swift"   emit_test   "$m"
done

echo ""
note "Done — ${WROTE} file(s) written, ${SKIPPED} skipped."

# --- Next steps --------------------------------------------------------------
umbrella_hint="$([[ "$HAS_UMBRELLA" -eq 1 ]] && echo "AppCore" || echo "${MODULES[0]}")"
cat <<EOF

Next steps:
  1. Verify it builds:   (cd "$PKG_NAME" && swift build && swift test)
  2. Add to Xcode:       File ▸ Add Package Dependencies… ▸ Add Local… ▸ select "$PKG_NAME"
  3. Link the product:   add "$umbrella_hint" to your app target's "Frameworks, Libraries, and Embedded Content"
  4. Move code in, leaf-first (Core before features). Make moved symbols \`public\`; build after each move.

See apple-modular-architecture.md for the incremental-migration playbook.
EOF
