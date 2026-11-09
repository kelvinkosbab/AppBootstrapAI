#!/usr/bin/env bash
# Smoke test, scaffold-spm-package.sh output.
# Run one part with `bash .github/scripts/smoke/scaffold.sh`, or all of them
# with `bash .github/scripts/install-smoke-test.sh`.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

bold "==> scaffold-spm-package.sh generates a valid KozBon-style package skeleton"
t="$(mktemp -d)"; mkdir -p "$t/MyApp"
"$REPO_ROOT/scripts/scaffold-spm-package.sh" "$t/MyApp" --modules Core,Models,AppCore > /dev/null
pkg="$t/MyApp/MyAppPackages"
scaffold_ok=y
for f in "$pkg/Package.swift" "$pkg/.gitignore" \
         "$pkg/Core/Sources/Core.swift" "$pkg/Core/Tests/CoreTests.swift" \
         "$pkg/Models/Sources/Models.swift" "$pkg/Models/Tests/ModelsTests.swift" \
         "$pkg/AppCore/Sources/AppCore.swift" "$pkg/AppCore/Tests/AppCoreTests.swift"; do
    [[ -f "$f" ]] || scaffold_ok=n
done
# AppCore umbrella must depend on the other two modules; products must be emitted.
grep -q 'makeTargets(' "$pkg/Package.swift" || scaffold_ok=n
grep -q '.library(name: "AppCore", targets: \["AppCore"\])' "$pkg/Package.swift" || scaffold_ok=n
grep -q '"Models"' "$pkg/Package.swift" || scaffold_ok=n
# Only the umbrella is a product; placeholders aren't named like their module.
grep -q '.library(name: "Core"' "$pkg/Package.swift" && scaffold_ok=n
grep -q 'public enum CorePlaceholder' "$pkg/Core/Sources/Core.swift" || scaffold_ok=n
grep -q 'public enum Core ' "$pkg/Core/Sources/Core.swift" && scaffold_ok=n
grep -q 'public struct AppRootView: View' "$pkg/AppCore/Sources/AppCore.swift" || scaffold_ok=n
grep -q 'swift-tools-version: 6.0' "$pkg/Package.swift" || scaffold_ok=n
grep -q 'defaultIsolation' "$pkg/Package.swift" && scaffold_ok=n
if [[ "$scaffold_ok" == "y" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: scaffold-spm-package.sh did not produce the expected package skeleton"
    FAIL=$((FAIL + 1))
fi
# Non-destructive: a second run without --force must refuse.
if "$REPO_ROOT/scripts/scaffold-spm-package.sh" "$t/MyApp" --modules Core,Models,AppCore >/dev/null 2>&1; then
    red "FAIL: scaffold-spm-package.sh should refuse to overwrite an existing package without --force"
    FAIL=$((FAIL + 1))
else
    PASS=$((PASS + 1))
fi
rm -rf "$t"

bold "==> scaffold --main-actor writes a tools-6.2 manifest with per-module default isolation"
t="$(mktemp -d)"; mkdir -p "$t/MyApp"
"$REPO_ROOT/scripts/scaffold-spm-package.sh" "$t/MyApp" --modules Core,Feature,AppCore --main-actor all > /dev/null
pkg="$t/MyApp/MyAppPackages"
actor_ok=y
grep -q 'swift-tools-version: 6.2' "$pkg/Package.swift" || actor_ok=n
grep -q '.defaultIsolation(MainActor.self)' "$pkg/Package.swift" || actor_ok=n
grep -q 'makeTargets(name: "Feature", swiftSettings: mainActorByDefault)' "$pkg/Package.swift" || actor_ok=n
grep -q 'makeTargets(name: "Core")$' "$pkg/Package.swift" || actor_ok=n
if [[ "$actor_ok" == "y" ]]; then PASS=$((PASS + 1)); else red "FAIL: scaffold --main-actor output is wrong"; FAIL=$((FAIL + 1)); fi
for bad in "Core,Core" "Testing" "CoreTests"; do
    if "$REPO_ROOT/scripts/scaffold-spm-package.sh" "$t/MyApp" --name Other --modules "$bad" --dry-run >/dev/null 2>&1; then
        red "FAIL: scaffold should reject module list '$bad'"; FAIL=$((FAIL + 1))
    else
        PASS=$((PASS + 1))
    fi
done
rm -rf "$t"

finish
