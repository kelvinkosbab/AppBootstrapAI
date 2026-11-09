#!/usr/bin/env bash
# Smoke test, per-category installs: sync commands, ai, persistence, packaging, ui, architecture, logging, linting, motion, compliance, deployment, spatial, and the --apple-platforms / --android-platforms selectors.
# Run one part with `bash .github/scripts/smoke/categories.sh`, or all of them
# with `bash .github/scripts/install-smoke-test.sh`.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# --- /appbootstrap-sync commands + bundle location ---------------------------

bold "==> install: writes /appbootstrap-sync and /appbootstrap-audit per agent and records the bundle"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --agents claude,cursor,copilot,gemini,codex > /dev/null 2>&1
m="$t/.claude/.appbootstrap-manifest.json"
if [[ -f "$t/.claude/commands/appbootstrap-sync.md" && -f "$t/.cursor/commands/appbootstrap-sync.md" \
      && -f "$t/.github/prompts/appbootstrap-sync.prompt.md" && -f "$t/.gemini/commands/appbootstrap-sync.toml" \
      && -f "$t/.claude/commands/appbootstrap-audit.md" && -f "$t/.cursor/commands/appbootstrap-audit.md" \
      && -f "$t/.github/prompts/appbootstrap-audit.prompt.md" && -f "$t/.gemini/commands/appbootstrap-audit.toml" ]] \
   && grep -q "playbooks/sync-and-audit.md" "$t/AGENTS.md" \
   && python3 -c "import json,sys; m=json.load(open(sys.argv[1])); assert m['bundle']['path']==sys.argv[2] and m['bundle']['repo'].startswith(('https://','git@')); assert len([f for f in m['files'] if f['type']=='agent-command'])==8" "$m" "$REPO_ROOT" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: install should write /appbootstrap-sync and /appbootstrap-audit for four agents and record bundle.path/repo"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> upgrade: adds the sync command to an install that predates it"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple > /dev/null 2>&1
rm -rf "$t/.claude/commands"
python3 -c "import json,sys; p=sys.argv[1]; m=json.load(open(p)); m['files']=[f for f in m['files'] if f['type']!='agent-command']; m.pop('bundle'); json.dump(m,open(p,'w'))" "$t/.claude/.appbootstrap-manifest.json"
"$INSTALL" upgrade "$t" --apply > /dev/null 2>&1
if [[ -f "$t/.claude/commands/appbootstrap-sync.md" && -f "$t/.claude/commands/appbootstrap-audit.md" ]] \
   && python3 -c "import json,sys; m=json.load(open(sys.argv[1])); assert m['bundle']['path']" "$t/.claude/.appbootstrap-manifest.json" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: upgrade --apply should add the missing sync command and record the bundle"
    FAIL=$((FAIL + 1))
fi
"$INSTALL" uninstall "$t" > /dev/null 2>&1
[[ ! -e "$t/.claude/commands/appbootstrap-sync.md" && ! -e "$t/.claude/commands/appbootstrap-audit.md" ]] && PASS=$((PASS + 1)) \
    || { red "FAIL: uninstall should remove the sync command"; FAIL=$((FAIL + 1)); }
rm -rf "$t"

# --- ai category is cross-platform; new skills land (v1.0 additions) ---------

bold "==> ai: --platform android --features ai installs the android AI rule (was empty)"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features ai > /dev/null
if [[ -f "$t/.claude/rules/android-ai-best-practices.md" \
   && ! -f "$t/.claude/rules/apple-foundation-models.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: android+ai should install android-ai-best-practices.md only"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> ai: --platform both --features ai installs both AI rules"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform both --features ai > /dev/null
if [[ -f "$t/.claude/rules/android-ai-best-practices.md" \
   && -f "$t/.claude/rules/apple-foundation-models.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: both+ai should install Apple AND Android AI rules"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> persistence: apple install includes swiftdata-pro alongside coredata-swift6-pro"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features persistence > /dev/null
if [[ -f "$t/.claude/skills/swiftdata-pro/SKILL.md" \
   && -f "$t/.claude/skills/coredata-swift6-pro/SKILL.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: persistence should install swiftdata-pro + coredata-swift6-pro"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> android recommended includes the new compose/coroutines skills"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features recommended > /dev/null
if [[ -f "$t/.claude/skills/android-compose-pro/SKILL.md" \
   && -f "$t/.claude/skills/android-coroutines-pro/SKILL.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: android recommended should install android-compose-pro + android-coroutines-pro"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> packaging: apple-modular-architecture lands for apple (recommended), not android"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
a_ok=$([[ -f "$t/.claude/rules/apple-modular-architecture.md" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features all > /dev/null
b_ok=$([[ ! -f "$t/.claude/rules/apple-modular-architecture.md" ]] && echo y)
rm -rf "$t"
if [[ "$a_ok" == "y" && "$b_ok" == "y" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: apple-modular-architecture should install for apple recommended and be absent for android"
    FAIL=$((FAIL + 1))
fi

bold "==> packaging: modularization rules + skills land per-platform (apple vs android, no cross-leak)"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
a_ok=$([[ -f "$t/.claude/skills/swift-modularization-pro/references/audit.md" \
       && ! -f "$t/.claude/rules/android-modular-architecture.md" \
       && ! -d "$t/.claude/skills/android-modularization-pro" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features packaging > /dev/null
b_ok=$([[ -f "$t/.claude/rules/android-modular-architecture.md" \
       && -f "$t/.claude/skills/android-modularization-pro/references/audit.md" \
       && ! -d "$t/.claude/skills/swift-modularization-pro" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform both --features core,testing > /dev/null
c_ok=$([[ ! -f "$t/.claude/rules/android-modular-architecture.md" \
       && ! -d "$t/.claude/skills/swift-modularization-pro" \
       && ! -d "$t/.claude/skills/android-modularization-pro" ]] && echo y)
rm -rf "$t"
if [[ "$a_ok" == "y" && "$b_ok" == "y" && "$c_ok" == "y" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: modularization rules/skills should follow platform + packaging feature (apple=$a_ok android=$b_ok no-packaging=$c_ok)"
    FAIL=$((FAIL + 1))
fi


bold "==> ui: adaptive-layout rule + skill land per-platform (apple vs android, no cross-leak)"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
a_ok=$([[ -f "$t/.claude/rules/apple-adaptive-layout.md" \
       && -f "$t/.claude/skills/swift-adaptive-layout-pro/SKILL.md" \
       && ! -d "$t/.claude/skills/android-adaptive-layout-pro" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features all > /dev/null
b_ok=$([[ ! -f "$t/.claude/rules/apple-adaptive-layout.md" \
       && ! -d "$t/.claude/skills/swift-adaptive-layout-pro" \
       && -d "$t/.claude/skills/android-adaptive-layout-pro" ]] && echo y)
rm -rf "$t"
if [[ "$a_ok" == "y" && "$b_ok" == "y" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: adaptive-layout rule/skill should install for their own platform only (apple=$a_ok android=$b_ok)"
    FAIL=$((FAIL + 1))
fi

bold "==> ui: iconography + design-system rules/skills land per-platform (apple vs android, no cross-leak)"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
a_ok=$([[ -f "$t/.claude/rules/apple-iconography.md" \
       && -f "$t/.claude/rules/apple-design-system.md" \
       && -f "$t/.claude/skills/swift-design-system-pro/references/bootstrap.md" \
       && ! -f "$t/.claude/rules/android-iconography.md" \
       && ! -d "$t/.claude/skills/android-design-system-pro" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features ui > /dev/null
b_ok=$([[ -f "$t/.claude/rules/android-iconography.md" \
       && -f "$t/.claude/rules/android-design-system.md" \
       && -f "$t/.claude/skills/android-design-system-pro/references/bootstrap.md" \
       && ! -f "$t/.claude/rules/apple-iconography.md" \
       && ! -d "$t/.claude/skills/swift-design-system-pro" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform both --features core,testing > /dev/null
c_ok=$([[ ! -f "$t/.claude/rules/apple-design-system.md" \
       && ! -f "$t/.claude/rules/android-design-system.md" ]] && echo y)
rm -rf "$t"
if [[ "$a_ok" == "y" && "$b_ok" == "y" && "$c_ok" == "y" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: design-system/iconography should follow platform + ui feature (apple=$a_ok android=$b_ok no-ui=$c_ok)"
    FAIL=$((FAIL + 1))
fi

bold "==> core: cross-platform rule + skill install only with --platform both"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform both --features recommended > /dev/null
a_ok=$([[ -f "$t/.claude/rules/cross-platform-development.md" \
       && -f "$t/.claude/skills/cross-platform-parity-pro/references/concept-map.md" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
b_ok=$([[ ! -f "$t/.claude/rules/cross-platform-development.md" \
       && ! -d "$t/.claude/skills/cross-platform-parity-pro" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features recommended > /dev/null
c_ok=$([[ ! -f "$t/.claude/rules/cross-platform-development.md" \
       && ! -d "$t/.claude/skills/cross-platform-parity-pro" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform both --features testing > /dev/null
d_ok=$([[ ! -f "$t/.claude/rules/cross-platform-development.md" ]] && echo y)
rm -rf "$t"
if [[ "$a_ok" == "y" && "$b_ok" == "y" && "$c_ok" == "y" && "$d_ok" == "y" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: cross-platform content gating (both=$a_ok apple=$b_ok android=$c_ok no-core=$d_ok)"
    FAIL=$((FAIL + 1))
fi

bold "==> architecture: MVVM + repository rules are opt-in and per-platform"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform both --features recommended > /dev/null
a_ok=$([[ ! -f "$t/.claude/rules/android-mvvm-architecture.md" \
       && ! -f "$t/.claude/rules/apple-repository-pattern.md" \
       && ! -f "$t/.claude/rules/android-repository-pattern.md" \
       && -f "$t/.claude/rules/apple-swiftui-mvvm.md" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended,architecture > /dev/null
b_ok=$([[ -f "$t/.claude/rules/apple-repository-pattern.md" \
       && ! -f "$t/.claude/rules/android-repository-pattern.md" \
       && ! -f "$t/.claude/rules/android-mvvm-architecture.md" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features recommended,architecture > /dev/null
c_ok=$([[ -f "$t/.claude/rules/android-mvvm-architecture.md" \
       && -f "$t/.claude/rules/android-repository-pattern.md" \
       && ! -f "$t/.claude/rules/apple-repository-pattern.md" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
mkdir -p "$t/app/src/main/java"
printf 'interface TasksRepository\n' > "$t/app/src/main/java/TasksRepository.kt"
d_ok=$("$INSTALL" recommend "$t" --json 2>/dev/null | python3 -c 'import json,sys; print("y" if "architecture" in json.load(sys.stdin)["features"] else "n")')
rm -rf "$t"
if [[ "$a_ok" == "y" && "$b_ok" == "y" && "$c_ok" == "y" && "$d_ok" == "y" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: architecture opt-in (recommended-excludes=$a_ok apple=$b_ok android=$c_ok recommend-detects=$d_ok)"
    FAIL=$((FAIL + 1))
fi

bold "==> ui: a11y skills land per-platform (swift- for apple, android- for android, no cross-leak)"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
a_ok=$([[ -f "$t/.claude/skills/swift-accessibility-pro/SKILL.md" \
       && ! -d "$t/.claude/skills/android-accessibility-pro" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features recommended > /dev/null
b_ok=$([[ -f "$t/.claude/skills/android-accessibility-pro/SKILL.md" \
       && ! -d "$t/.claude/skills/swift-accessibility-pro" ]] && echo y)
rm -rf "$t"
if [[ "$a_ok" == "y" && "$b_ok" == "y" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: a11y skills should install under ui for their own platform only"
    FAIL=$((FAIL + 1))
fi

bold "==> core: concise-comments-and-commits rule lands on BOTH platforms"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features core > /dev/null
a_ok=$([[ -f "$t/.claude/rules/concise-comments-and-commits.md" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features core > /dev/null
b_ok=$([[ -f "$t/.claude/rules/concise-comments-and-commits.md" ]] && echo y)
rm -rf "$t"
if [[ "$a_ok" == "y" && "$b_ok" == "y" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: concise-comments-and-commits should install under core for apple AND android"
    FAIL=$((FAIL + 1))
fi


# --- logging rules (filling the Android gap) ---------------------------------

bold "==> logging: --platform android --features logging now installs the android rule (was empty)"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features logging > /dev/null
if [[ -f "$t/.claude/rules/android-logging-strategy.md" \
   && ! -f "$t/.claude/rules/apple-logging-strategy.md" \
   && ! -d "$t/.claude/skills/swift-logging-pro" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: android logging should install the android rule, exclude apple rule + swift skill"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> logging: --platform apple → apple rule + swift-logging-pro skill, not android rule"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features logging > /dev/null
if [[ -f "$t/.claude/rules/apple-logging-strategy.md" \
   && -d "$t/.claude/skills/swift-logging-pro" \
   && ! -f "$t/.claude/rules/android-logging-strategy.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: apple logging should install apple rule + skill, exclude android rule"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> logging: manifest categorizes both logging rules as 'logging'"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform both --features logging > /dev/null
if python3 -c "
import json
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
cats = {f['path']: f['category'] for f in m['files'] if 'logging-strategy' in f['path']}
assert cats.get('.claude/rules/apple-logging-strategy.md') == 'logging', cats
assert cats.get('.claude/rules/android-logging-strategy.md') == 'logging', cats
" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: manifest should categorize both logging rules as 'logging'"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

# --- linting category (in `recommended`) -------------------------------------

bold "==> linting is IN recommended → both linting rules install by default"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform both --features recommended > /dev/null
if [[ -f "$t/.claude/rules/apple-linting-strategy.md" \
   && -f "$t/.claude/rules/android-linting-strategy.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: linting rules should install under default --features recommended"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --platform apple → only apple-linting-strategy, not android"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
if [[ -f "$t/.claude/rules/apple-linting-strategy.md" \
   && ! -f "$t/.claude/rules/android-linting-strategy.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --platform apple should install apple linting rule, exclude android"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --platform android → only android-linting-strategy, not apple"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features recommended > /dev/null
if [[ -f "$t/.claude/rules/android-linting-strategy.md" \
   && ! -f "$t/.claude/rules/apple-linting-strategy.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --platform android should install android linting rule, exclude apple"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> excluding linting: --features recommended minus linting is honored via explicit CSV"
t="$(mktemp -d)"
# An explicit CSV without 'linting' must NOT pull the linting rules in.
"$INSTALL" "$t" --platform both --features core,testing > /dev/null
if [[ ! -f "$t/.claude/rules/apple-linting-strategy.md" \
   && ! -f "$t/.claude/rules/android-linting-strategy.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: a CSV without 'linting' should not install the linting rules"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> manifest records linting rules' category as 'linting'"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform both --features recommended > /dev/null
if python3 -c "
import json
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
cats = {f['path']: f['category'] for f in m['files'] if 'linting-strategy' in f['path']}
assert cats.get('.claude/rules/apple-linting-strategy.md') == 'linting', cats
assert cats.get('.claude/rules/android-linting-strategy.md') == 'linting', cats
" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: manifest should categorize both linting rules as 'linting'"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

# --- motion design (ui) --------------------------------------------------------

bold "==> motion: rules follow platform, motion-design-pro lands for either, audit --topic motion flags loops"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android > /dev/null
m_ok=$([[ -f "$t/.claude/rules/android-motion-design.md" \
       && ! -f "$t/.claude/rules/apple-motion-design.md" \
       && -f "$t/.claude/skills/motion-design-pro/references/motion-spec.md" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --apple-language objc > /dev/null
o_ok=$([[ ! -d "$t/.claude/skills/motion-design-pro" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
mkdir -p "$t/Sources/App"
printf 'let a = Animation.easeInOut.repeatForever()\n' > "$t/Sources/App/Loop.swift"
printf '@Environment(\\.accessibilityReduceMotion) var r\nlet a = Animation.easeInOut.repeatForever()\n' > "$t/Sources/App/Guarded.swift"
mo="$("$INSTALL" audit "$t" --no-install-check --no-baseline --topic motion --json 2>&1)"
rm -rf "$t"
if [[ "$m_ok" == "y" && "$o_ok" == "y" ]] && python3 -c "
import json, sys
d = json.loads(sys.argv[1])
f = {x['id']: x for x in d['findings']}
assert f['swift-motion-loop-no-reduce-motion']['locations'] == ['Sources/App/Loop.swift:1'], f
assert [s['skill'] for s in d['skills_to_run']] == ['motion-design-pro']
" "$mo" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: motion rules/skill scoping or the motion audit check (android=$m_ok objc-only=$o_ok)"
    FAIL=$((FAIL + 1))
fi

# --- compliance category (regional store rules) ------------------------------

bold "==> compliance: regional rules + store-compliance-pro land per platform in recommended"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple > /dev/null
a_ok=$([[ -f "$t/.claude/rules/apple-regional-compliance.md" \
       && ! -f "$t/.claude/rules/android-regional-compliance.md" \
       && -f "$t/.claude/skills/store-compliance-pro/references/audit.md" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android > /dev/null
b_ok=$([[ -f "$t/.claude/rules/android-regional-compliance.md" \
       && ! -f "$t/.claude/rules/apple-regional-compliance.md" \
       && -f "$t/.claude/skills/store-compliance-pro/SKILL.md" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform both --features core,testing > /dev/null
c_ok=$([[ ! -f "$t/.claude/rules/apple-regional-compliance.md" \
       && ! -f "$t/.claude/rules/android-regional-compliance.md" \
       && ! -d "$t/.claude/skills/store-compliance-pro" ]] && echo y)
rm -rf "$t"
if [[ "$a_ok" == "y" && "$b_ok" == "y" && "$c_ok" == "y" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: compliance rules/skill should follow platform + compliance feature (apple=$a_ok android=$b_ok no-compliance=$c_ok)"
    FAIL=$((FAIL + 1))
fi

# --- deployment category (TestFlight + Play beta) ----------------------------

bold "==> --features recommended (default) → deployment rules NOT installed"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform both --features recommended > /dev/null
if [[ ! -f "$t/.claude/rules/apple-testflight-deployment.md" \
   && ! -f "$t/.claude/rules/android-play-beta-deployment.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: deployment rules should be excluded from default --features recommended"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --features recommended,deployment → BOTH deployment rules installed"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform both --features recommended,deployment > /dev/null
if [[ -f "$t/.claude/rules/apple-testflight-deployment.md" \
   && -f "$t/.claude/rules/android-play-beta-deployment.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --features recommended,deployment should install both rules on --platform both"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --features all → BOTH deployment rules installed"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform both --features all > /dev/null
if [[ -f "$t/.claude/rules/apple-testflight-deployment.md" \
   && -f "$t/.claude/rules/android-play-beta-deployment.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --features all should install both deployment rules"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --platform apple --features deployment → only apple-testflight, not android-play"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features deployment > /dev/null
if [[ -f "$t/.claude/rules/apple-testflight-deployment.md" \
   && ! -f "$t/.claude/rules/android-play-beta-deployment.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --platform apple should install TestFlight rule, exclude Play rule"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --platform android --features deployment → only android-play, not apple-testflight"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features deployment > /dev/null
if [[ -f "$t/.claude/rules/android-play-beta-deployment.md" \
   && ! -f "$t/.claude/rules/apple-testflight-deployment.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --platform android should install Play rule, exclude TestFlight rule"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> manifest records deployment rules' category as 'deployment'"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform both --features all > /dev/null
if python3 -c "
import json
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
matches = {f['path']: f['category'] for f in m['files']
           if 'deployment' in f['path']}
assert matches.get('.claude/rules/apple-testflight-deployment.md') == 'deployment', matches
assert matches.get('.claude/rules/android-play-beta-deployment.md') == 'deployment', matches
" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: manifest should categorize both deployment rules as 'deployment'"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

# --- spatial / visionOS category (Phase 8) ----------------------------------

bold "==> --features recommended (default) → visionOS rule NOT installed"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
if [[ ! -f "$t/.claude/rules/apple-visionos-best-practices.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: visionOS rule should be excluded from default --features recommended"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --features recommended,spatial → visionOS rule installed"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended,spatial > /dev/null
if [[ -f "$t/.claude/rules/apple-visionos-best-practices.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --features recommended,spatial should install the visionOS rule"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --features all → visionOS rule installed"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features all > /dev/null
if [[ -f "$t/.claude/rules/apple-visionos-best-practices.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --features all should install the visionOS rule"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --platform android --features spatial → visionOS rule NOT installed (apple-only)"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features spatial > /dev/null
if [[ ! -f "$t/.claude/rules/apple-visionos-best-practices.md" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: Android-only install should never get apple-visionos-best-practices.md"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> manifest records visionOS rule's category as 'spatial'"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features all > /dev/null
if python3 -c "
import json, sys
m = json.load(open('$t/.claude/.appbootstrap-manifest.json'))
matches = [f for f in m['files'] if f['path'] == '.claude/rules/apple-visionos-best-practices.md']
assert matches, 'visionOS rule not in manifest'
assert matches[0]['category'] == 'spatial', f'wrong category: {matches[0]}'
" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: manifest should categorize visionOS rule as 'spatial'"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

# --- --apple-platforms selector ----------------------------------------------

bold "==> --apple-platforms default omits visionOS; records resolved set"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
if [[ ! -f "$t/.claude/rules/apple-visionos-best-practices.md" ]] && python3 -c "
import json
s = json.load(open('$t/.claude/.appbootstrap-manifest.json'))['selection']
assert s['apple_platforms_resolved'] == ['ios','macos','tvos','watchos'], s['apple_platforms_resolved']
assert 'spatial' not in s['features_resolved']
" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: default --apple-platforms should be the four non-visionOS platforms, no visionOS rule"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --apple-platforms ios,visionos → visionOS rule installs (spatial synced)"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --apple-platforms ios,visionos > /dev/null
if [[ -f "$t/.claude/rules/apple-visionos-best-practices.md" ]] && python3 -c "
import json
s = json.load(open('$t/.claude/.appbootstrap-manifest.json'))['selection']
assert 'visionos' in s['apple_platforms_resolved']
assert 'spatial' in s['features_resolved']
" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: --apple-platforms ...,visionos should install the visionOS rule and sync spatial"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --apple-platforms all → visionOS included"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --apple-platforms all > /dev/null
[[ -f "$t/.claude/rules/apple-visionos-best-practices.md" ]] && PASS=$((PASS + 1)) \
    || { red "FAIL: --apple-platforms all should include visionOS"; FAIL=$((FAIL + 1)); }
rm -rf "$t"

bold "==> --features ...,spatial back-syncs visionos into apple_platforms_resolved"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended,spatial > /dev/null
python3 -c "
import json
s = json.load(open('$t/.claude/.appbootstrap-manifest.json'))['selection']
assert 'visionos' in s['apple_platforms_resolved'], s['apple_platforms_resolved']
" 2>/dev/null && PASS=$((PASS + 1)) \
    || { red "FAIL: --features spatial should back-sync visionos into apple_platforms_resolved"; FAIL=$((FAIL + 1)); }
rm -rf "$t"

bold "==> --apple-platforms rejects an unknown token"
if "$INSTALL" /tmp/x --platform apple --apple-platforms ios,carplay > /tmp/ap.out 2>&1; then
    red "FAIL: unknown apple platform should error"; FAIL=$((FAIL + 1))
else
    grep -q "unknown apple platform" /tmp/ap.out && PASS=$((PASS + 1)) \
        || { red "FAIL: bad apple-platform error message changed"; FAIL=$((FAIL + 1)); }
fi
rm -f /tmp/ap.out

bold "==> --apple-platforms inherited on upgrade; round-trips clean"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --apple-platforms ios,visionos > /dev/null
up="$("$INSTALL" upgrade "$t" 2>&1)"
inherited="$(python3 -c "import json;print(json.load(open('$t/.claude/.appbootstrap-manifest.json'))['selection']['apple_platforms_input'])")"
if grep -q "0 safe update" <<<"$up" && grep -q "0 addition" <<<"$up" && [[ "$inherited" == "ios,visionos" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --apple-platforms should be recorded + inherited + round-trip clean on upgrade"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

# --- --apple-platforms selector (macos gates the touch-on-Mac rule) ----------

bold "==> --apple-platforms: default installs the touch-on-Mac rule; ios-only excludes it"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
def_ok=$([[ -f "$t/.claude/rules/apple-mac-touch.md" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended --apple-platforms ios > /dev/null
gate_ok=$([[ ! -f "$t/.claude/rules/apple-mac-touch.md" \
          && -f "$t/.claude/rules/apple-adaptive-layout.md" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --apple-language objc --features recommended > /dev/null
objc_ok=$([[ ! -f "$t/.claude/rules/apple-mac-touch.md" ]] && echo y)
rm -rf "$t"
if [[ "$def_ok" == "y" && "$gate_ok" == "y" && "$objc_ok" == "y" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: macos token should gate apple-mac-touch.md (def=$def_ok gate=$gate_ok objc=$objc_ok)"
    FAIL=$((FAIL + 1))
fi

# --- --android-platforms selector (tablet gates the large-screen rule + skill) -

bold "==> --android-platforms: default (phone,tablet) installs large-screen rule + skill; wear,tv excludes them"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features recommended > /dev/null
def_ok=$([[ -f "$t/.claude/rules/android-large-screen-best-practices.md" \
         && -f "$t/.claude/skills/android-adaptive-layout-pro/SKILL.md" ]] && echo y)
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features recommended --android-platforms wear,tv > /dev/null
gate_ok=$([[ ! -f "$t/.claude/rules/android-large-screen-best-practices.md" \
          && ! -d "$t/.claude/skills/android-adaptive-layout-pro" \
          && -f "$t/.claude/rules/android-compose-best-practices.md" ]] && echo y)
if [[ "$def_ok" == "y" && "$gate_ok" == "y" ]] && python3 -c "
import json
s = json.load(open('$t/.claude/.appbootstrap-manifest.json'))['selection']
assert s['android_platforms_resolved'] == ['wear','tv'], s['android_platforms_resolved']
" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: tablet token should gate the large-screen rule + adaptive-layout skill (def=$def_ok gate=$gate_ok)"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> --android-platforms default + 'all' resolve correctly"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features recommended > /dev/null
def_ok="$(python3 -c "import json;print(json.load(open('$t/.claude/.appbootstrap-manifest.json'))['selection']['android_platforms_resolved'] == ['phone','tablet'])")"
rm -rf "$t"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features recommended --android-platforms all > /dev/null
all_ok="$(python3 -c "import json;print(json.load(open('$t/.claude/.appbootstrap-manifest.json'))['selection']['android_platforms_resolved'] == ['phone','tablet','wear','tv','auto'])")"
rm -rf "$t"
[[ "$def_ok" == "True" && "$all_ok" == "True" ]] && PASS=$((PASS + 1)) \
    || { red "FAIL: android-platforms default/all resolution wrong (def=$def_ok all=$all_ok)"; FAIL=$((FAIL + 1)); }

bold "==> --android-platforms rejects an unknown token"
if "$INSTALL" /tmp/x --platform android --android-platforms phone,fridge > /tmp/anp.out 2>&1; then
    red "FAIL: unknown android platform should error"; FAIL=$((FAIL + 1))
else
    grep -q "unknown android platform" /tmp/anp.out && PASS=$((PASS + 1)) \
        || { red "FAIL: bad android-platform error message changed"; FAIL=$((FAIL + 1)); }
fi
rm -f /tmp/anp.out

bold "==> --android-platforms inherited on upgrade; round-trips clean"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform android --features recommended --android-platforms wear > /dev/null
up="$("$INSTALL" upgrade "$t" 2>&1)"
inh="$(python3 -c "import json;print(json.load(open('$t/.claude/.appbootstrap-manifest.json'))['selection']['android_platforms_input'])")"
if grep -q "0 safe update" <<<"$up" && grep -q "0 addition" <<<"$up" && [[ "$inh" == "wear" ]]; then
    PASS=$((PASS + 1))
else
    red "FAIL: --android-platforms should be recorded + inherited + round-trip clean"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

finish
