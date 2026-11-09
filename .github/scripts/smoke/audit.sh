#!/usr/bin/env bash
# Smoke test, recommend and audit: findings, topics, baselines, steering.
# Run one part with `bash .github/scripts/smoke/audit.sh`, or all of them
# with `bash .github/scripts/install-smoke-test.sh`.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# --- recommend (analyze a dir → suggested command) ---------------------------

bold "==> recommend: fresh Apple repo detects ai + persistence"
t="$(mktemp -d)"
touch "$t/Package.swift"
mkdir -p "$t/Sources" "$t/Model/My.xcdatamodeld"
printf 'import FoundationModels\n' > "$t/Sources/Chat.swift"
printf 'import CoreData\n' > "$t/Sources/Store.swift"
rec="$("$INSTALL" recommend "$t" 2>&1)"
if grep -q "platform:  apple" <<<"$rec" \
   && grep -q "recommended,persistence,ai" <<<"$rec" \
   && grep -qi "import FoundationModels" <<<"$rec" \
   && grep -q "install $t" <<<"$rec"; then
    PASS=$((PASS + 1))
else
    red "FAIL: recommend should detect apple + ai + persistence and emit an install command"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> recommend: Android repo detects persistence (Room) + shrinking (R8)"
t="$(mktemp -d)"
touch "$t/settings.gradle.kts" "$t/gradlew" "$t/proguard-rules.pro"
mkdir -p "$t/app/src"
printf 'import androidx.room.Entity\n' > "$t/app/src/U.kt"
rec="$("$INSTALL" recommend "$t" 2>&1)"
if grep -q "platform:  android" <<<"$rec" \
   && grep -q "persistence" <<<"$rec" && grep -q "shrinking" <<<"$rec"; then
    PASS=$((PASS + 1))
else
    red "FAIL: recommend should detect android + persistence + shrinking"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> recommend: managed dir routes to upgrade"
t="$(mktemp -d)"
"$INSTALL" "$t" --platform apple --features recommended > /dev/null
rec="$("$INSTALL" recommend "$t" 2>&1)"
if grep -q "state:     managed" <<<"$rec" \
   && grep -q "action:    upgrade" <<<"$rec" \
   && grep -q "upgrade $t --apply" <<<"$rec"; then
    PASS=$((PASS + 1))
else
    red "FAIL: recommend on a managed dir should suggest upgrade --apply"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> recommend: missing dir → create with --new"
rec="$("$INSTALL" recommend "/tmp/abai-rec-missing-$$" 2>&1)"
if grep -q "state:     missing" <<<"$rec" \
   && grep -q -- "--new" <<<"$rec"; then
    PASS=$((PASS + 1))
else
    red "FAIL: recommend on a missing dir should suggest install --new"
    FAIL=$((FAIL + 1))
fi

bold "==> recommend: unmanaged dir (.claude/rules, no manifest) → adopt"
t="$(mktemp -d)"
touch "$t/Package.swift"; mkdir -p "$t/.claude/rules"; touch "$t/.claude/rules/x.md"
rec="$("$INSTALL" recommend "$t" 2>&1)"
grep -q "state:     unmanaged" <<<"$rec" && PASS=$((PASS + 1)) \
    || { red "FAIL: recommend should classify a manifest-less .claude/rules dir as unmanaged"; FAIL=$((FAIL + 1)); }
rm -rf "$t"

bold "==> recommend --json emits a parseable object with command[]"
t="$(mktemp -d)"; touch "$t/build.gradle.kts" "$t/gradlew"
js="$("$INSTALL" recommend "$t" --json 2>&1)"
if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d['platform']=='android'; assert isinstance(d['command'],list) and d['command'][1]=='install'; assert d['state']=='fresh'" "$js" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: recommend --json should be a parseable object with a command array"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> recommend: --recommend flag alias works like the verb"
t="$(mktemp -d)"; touch "$t/Package.swift"
a="$("$INSTALL" recommend "$t" 2>&1)"
b="$("$INSTALL" --recommend "$t" 2>&1)"
[[ "$a" == "$b" && -n "$a" ]] && PASS=$((PASS + 1)) \
    || { red "FAIL: --recommend alias should match the recommend verb"; FAIL=$((FAIL + 1)); }
rm -rf "$t"

# --- audit (rule hotspots → findings + skills to run) ------------------------

bold "==> audit: flags try! in sources, skips it in tests, gates with --fail-on"
t="$(mktemp -d)"
touch "$t/Package.swift"
mkdir -p "$t/Sources" "$t/Tests"
printf 'let x = try! load()\n' > "$t/Sources/A.swift"
printf 'let y = try! load()\n' > "$t/Tests/ATests.swift"
out="$("$INSTALL" audit "$t" 2>&1)"; rc=$?
js="$("$INSTALL" audit "$t" --json 2>&1)"
set +e; "$INSTALL" audit "$t" --fail-on high > /dev/null 2>&1; gate=$?; set -e
if [[ "$rc" -eq 0 && "$gate" -eq 2 ]] && grep -q "Sources/A.swift:1" <<<"$out" \
   && python3 -c "import json,sys; d=json.loads(sys.argv[1]); f=[x for x in d['findings'] if x['id']=='swift-force-try'][0]; assert f['count']==1 and 'Tests' not in f['locations'][0]; assert d['skills_to_run']" "$js" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: audit should flag source try!, skip test try!, emit JSON, and exit 2 under --fail-on high"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> audit: Android large-screen restrictions flagged, games exempt"
t="$(mktemp -d)"; touch "$t/build.gradle.kts" "$t/gradlew"
mkdir -p "$t/app/src/main/java/a" "$t/game/src/main"
cat > "$t/app/src/main/AndroidManifest.xml" <<'XML'
<manifest>
  <application android:supportsRtl="true">
    <property android:name="android.window.PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY" android:value="true" />
    <activity android:name=".Main" android:screenOrientation="userPortrait" android:resizeableActivity="false" />
  </application>
</manifest>
XML
cat > "$t/game/src/main/AndroidManifest.xml" <<'XML'
<manifest>
  <application android:appCategory="game" android:supportsRtl="true">
    <activity android:name=".Game" android:screenOrientation="landscape" />
  </application>
</manifest>
XML
printf 'val tablet = resources.configuration.smallestScreenWidthDp >= 600\nval w = currentWindowAdaptiveInfo().windowSizeClass\nval v = currentWindowAdaptiveInfoV2()\nrequestedOrientation = 1\n' \
    > "$t/app/src/main/java/a/Main.kt"
js="$("$INSTALL" audit "$t" --json 2>&1)"
if python3 -c "
import json,sys
d={f['id']:f for f in json.loads(sys.argv[1])['findings']}
for i in ('android-orientation-lock','android-resizability-restricted','android-resizability-optout',
          'kt-device-heuristic','kt-requested-orientation','kt-window-size-class-v1'):
    assert d[i]['count']==1, i
    assert 'game/' not in d[i]['locations'][0], i
assert d['kt-window-size-class-v1']['locations']==['app/src/main/java/a/Main.kt:2']
" "$js" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: audit should flag manifest restrictions, the opt-out, and device heuristics, and skip game manifests"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> audit: --fail-on outside audit is rejected"
set +e; "$INSTALL" upgrade . --fail-on high > /dev/null 2>&1; rc=$?; set -e
[[ "$rc" -ne 0 ]] && PASS=$((PASS + 1)) \
    || { red "FAIL: --fail-on without audit should error"; FAIL=$((FAIL + 1)); }

bold "==> audit baseline: accepted findings don't trip --fail-on; new ones do"
t="$(mktemp -d)"
touch "$t/Package.swift"
mkdir -p "$t/Sources"
printf 'let a = try! f()\nlet b = try! g()\n' > "$t/Sources/A.swift"
"$INSTALL" audit "$t" --write-baseline --baseline-reason "legacy" > /dev/null 2>&1
bl="$t/.claude/appbootstrap-audit-baseline.json"
set +e; "$INSTALL" audit "$t" --fail-on high > /dev/null 2>&1; accepted=$?; set -e
printf 'let c = try! h()\n' >> "$t/Sources/A.swift"
set +e; "$INSTALL" audit "$t" --fail-on high > /dev/null 2>&1; added=$?; set -e
js="$("$INSTALL" audit "$t" --json 2>&1)"
all="$("$INSTALL" audit "$t" --no-baseline --json 2>&1)"
if [[ "$accepted" -eq 0 && "$added" -eq 2 ]] \
   && python3 -c "import json,sys; b=json.load(open(sys.argv[1])); e=[x for x in b['entries'] if x['id']=='swift-force-try'][0]; assert e['count']==2 and e['reason']=='legacy' and e['file']=='Sources/A.swift'" "$bl" 2>/dev/null \
   && python3 -c "import json,sys; d=json.loads(sys.argv[1]); f=[x for x in d['findings'] if x['id']=='swift-force-try'][0]; assert f['count']==1 and f['baselined']==2; a=json.loads(sys.argv[2]); assert a['baseline'] is None and [x for x in a['findings'] if x['id']=='swift-force-try'][0]['count']==3" "$js" "$all" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: baseline should accept 2 try!, gate only the 3rd, and --no-baseline should show all 3"
    FAIL=$((FAIL + 1))
fi
rm -f "$t/Sources/A.swift"
out="$("$INSTALL" audit "$t" 2>&1)"
grep -q "fixed: re-run with --write-baseline" <<<"$out" && PASS=$((PASS + 1)) \
    || { red "FAIL: baseline entries for fixed code should be reported as stale"; FAIL=$((FAIL + 1)); }
rm -rf "$t"

bold "==> audit steering: flags project steering files, skips bundle-installed ones"
t="$(mktemp -d)"
touch "$t/Package.swift"
mkdir -p "$t/Sources" "$t/.cursor/rules"
printf 'let x = 1\n' > "$t/Sources/A.swift"
"$INSTALL" "$t" --platform apple --features core > /dev/null 2>&1
cat > "$t/AGENTS.md" <<'MD'
# <PROJECT_NAME>

- Run `./scripts/build.sh` before committing.
- Shared code lives in `Sources/Gone/Helpers.swift`.
- Use `DispatchQueue.main.async` for UI updates.
- Follow best practices.
MD
printf -- '---\ndescription: testing\n---\nUse XCTest.\n' > "$t/.cursor/rules/testing.mdc"
printf '# Team\n\nUse tabs.\n' > "$t/.claude/rules/team.md"
js="$("$INSTALL" audit "$t" --json 2>&1)"
only="$("$INSTALL" audit "$t" --steering-only --json 2>&1)"
if python3 -c "
import json,sys
d=json.loads(sys.argv[1]); ids={f['id'] for f in d['findings']}
need={'steering-placeholder','steering-stale-command','steering-stale-path','steering-contradicts-bundle','steering-vague','steering-unscoped-rule'}
assert need <= ids, need - ids
st=d['steering']; owners={f['path']: f['owner'] for f in st['files']}
assert owners['AGENTS.md']=='project' and any(o=='bundle' for p,o in owners.items() if p.startswith('.claude/rules/'))
bundle={p for p,o in owners.items() if o=='bundle'}
assert not any(l.split(':')[0] in bundle for f in d['findings'] if f['id'].startswith('steering-') for l in f['locations'])
o=json.loads(sys.argv[2]); assert o['mode']=='steering' and not o['skills_to_run']
assert all(f['id'].startswith('steering-') for f in o['findings'])
" "$js" "$only" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: audit should flag project steering files, skip bundle-installed rules, and --steering-only should report steering findings only"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> audit steering: --steering-only outside audit is rejected"
set +e; "$INSTALL" upgrade . --steering-only > /dev/null 2>&1; rc=$?; set -e
[[ "$rc" -ne 0 ]] && PASS=$((PASS + 1)) \
    || { red "FAIL: --steering-only without audit should error"; FAIL=$((FAIL + 1)); }

bold "==> audit --topic: keeps one area's findings, skills, and files to read"
t="$(mktemp -d)"
mkdir -p "$t/Sources/App"
printf 'final class Box: @unchecked Sendable {}\nlet w = UIScreen.main.bounds\n' > "$t/Sources/App/A.swift"
conc="$("$INSTALL" audit "$t" --no-install-check --no-baseline --topic concurrency --json 2>&1)"
arch="$("$INSTALL" audit "$t" --no-install-check --no-baseline --topic architecture --json 2>&1)"
ui="$("$INSTALL" audit "$t" --no-install-check --no-baseline --topic ui --json 2>&1)"
docs="$("$INSTALL" audit "$t" --no-install-check --no-baseline --topic docs --json 2>&1)"
if python3 -c "
import json, sys
c, a = json.loads(sys.argv[1]), json.loads(sys.argv[2])
ids = [f['id'] for f in c['findings']]
assert 'swift-unchecked-sendable' in ids and 'swift-uiscreen-main' not in ids, ids
assert c['topic']['name'] == 'concurrency' and c['steering'] is None
assert {s['skill'] for s in c['skills_to_run']} <= set(c['topic']['skills'])
assert all(__import__('os').path.isfile(p) for p in c['topic']['rule_paths'] + c['topic']['skill_paths'])
assert not a['findings'] and 'swift-modularization-pro' in [s['skill'] for s in a['skills_to_run']]
u, d = json.loads(sys.argv[3]), json.loads(sys.argv[4])
uids = [f['id'] for f in u['findings']]
assert 'swift-uiscreen-main' in uids and 'swift-unchecked-sendable' not in uids, uids
assert 'project-documentation.md' in d['topic']['rules'] and 'swift-docc-pro' in d['topic']['skills']
" "$conc" "$arch" "$ui" "$docs" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: audit --topic should keep only that topic's findings and skills"
    FAIL=$((FAIL + 1))
fi
set +e
"$INSTALL" audit "$t" --topic nope > /dev/null 2>&1; r1=$?
"$INSTALL" upgrade . --topic concurrency > /dev/null 2>&1; r2=$?
"$INSTALL" audit "$t" --topic concurrency --steering-only > /dev/null 2>&1; r3=$?
set -e
[[ "$r1" -ne 0 && "$r2" -ne 0 && "$r3" -ne 0 ]] && PASS=$((PASS + 1)) \
    || { red "FAIL: --topic should reject unknown names, non-audit verbs, and --steering-only"; FAIL=$((FAIL + 1)); }
rm -rf "$t"

bold "==> audit memory/storage: checks fire and each topic keeps only its half"
t="$(mktemp -d)"
mkdir -p "$t/App.xcodeproj" "$t/Sources/App" "$t/app/src/main/java/x"
: > "$t/App.xcodeproj/project.pbxproj"
cat > "$t/Sources/App/Feed.swift" <<'SWIFT'
final class Feed {
    var delegate: FeedDelegate?
    weak var other: FeedDelegate?
    func start() {
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        UserDefaults.standard.set(token, forKey: "authToken")
        let free = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    }
}
protocol P { var delegate: FeedDelegate? { get set } }
SWIFT
printf '<plist><string>NSPrivacyAccessedAPICategoryUserDefaults</string></plist>\n' > "$t/Sources/App/PrivacyInfo.xcprivacy"
printf 'dependencies { implementation("androidx.security:security-crypto:1.1.0") }\n' > "$t/app/build.gradle.kts"
printf 'include(":app")\n' > "$t/settings.gradle.kts"
cat > "$t/app/src/main/AndroidManifest.xml" <<'XML'
<manifest>
    <uses-permission
        android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />
    <application android:largeHeap="true" android:supportsRtl="true"></application>
</manifest>
XML
cat > "$t/app/src/main/java/x/Main.kt" <<'KT'
class ProfileViewModel(private val activity: Activity) : ViewModel()
fun f() { prefs.edit().putString("auth_token", t).commit() }
KT
mem="$("$INSTALL" audit "$t" --no-install-check --no-baseline --topic memory --json 2>&1)"
sto="$("$INSTALL" audit "$t" --no-install-check --no-baseline --topic storage --json 2>&1)"
if python3 -c "
import json, sys
m, s = json.loads(sys.argv[1]), json.loads(sys.argv[2])
mids, sids = {f['id'] for f in m['findings']}, {f['id'] for f in s['findings']}
assert {'swift-strong-delegate', 'swift-timer-retains-self', 'kt-viewmodel-holds-ui',
        'kt-large-heap', 'android-no-leakcanary'} <= mids, mids
assert {'swift-secret-in-defaults', 'apple-privacy-disk-space', 'kt-prefs-commit', 'kt-secret-in-prefs',
        'kt-security-crypto', 'android-all-files-access', 'android-backup-unscoped'} <= sids, sids
assert not mids & sids, mids & sids
assert 'android-legacy-storage-permission' not in sids, 'maxSdkVersion on the next line should pass'
delegate = next(f for f in m['findings'] if f['id'] == 'swift-strong-delegate')
assert delegate['count'] == 1, delegate['locations']
assert sorted(m['topic']['rules']) == ['android-memory-management.md', 'apple-memory-management.md'], m['topic']['rules']
assert {x['skill'] for x in s['skills_to_run']} == {'swift-memory-storage-pro', 'android-memory-storage-pro'}
" "$mem" "$sto"; then
    PASS=$((PASS + 1))
else
    red "FAIL: memory/storage checks should fire and split cleanly between the two topics"
    FAIL=$((FAIL + 1))
fi
rm -rf "$t"

bold "==> audit baseline: flags are audit-only and validated"
set +e
"$INSTALL" upgrade . --write-baseline > /dev/null 2>&1; r1=$?
"$INSTALL" audit . --no-baseline --write-baseline > /dev/null 2>&1; r2=$?
"$INSTALL" audit . --baseline-reason x > /dev/null 2>&1; r3=$?
set -e
[[ "$r1" -ne 0 && "$r2" -ne 0 && "$r3" -ne 0 ]] && PASS=$((PASS + 1)) \
    || { red "FAIL: baseline flags should be rejected outside audit or in bad combinations"; FAIL=$((FAIL + 1)); }

bold "==> audit: --no-install-check audits a library without the install findings"
t="$(mktemp -d)"
touch "$t/Package.swift"
mkdir -p "$t/Sources"
printf 'let x = try! load()\n' > "$t/Sources/A.swift"
js="$("$INSTALL" audit "$t" --no-install-check --json 2>&1)"
full="$("$INSTALL" audit "$t" --json 2>&1)"
set +e; "$INSTALL" upgrade . --no-install-check > /dev/null 2>&1; bad=$?; set -e
if [[ "$bad" -ne 0 && -z "$(ls -A "$t/.claude" 2>/dev/null)" ]] \
   && python3 -c "
import json, sys
d = json.loads(sys.argv[1]); f = json.loads(sys.argv[2])
ids = [x['id'] for x in d['findings']]
skills = [s['skill'] for s in d['skills_to_run']]
assert d['kind'] == 'package' and d['playbook'].endswith('playbooks/audit.md')
assert 'bundle-not-installed' not in ids and 'no-compliance-register' not in ids
assert 'swift-package-pro' in skills and 'swift-design-system-pro' not in skills
assert 'bundle-not-installed' in [x['id'] for x in f['findings']]
" "$js" "$full" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    red "FAIL: --no-install-check should drop install findings, tag a Package.swift repo as a package, and suggest library reviews"
    FAIL=$((FAIL + 1))
fi
mkdir -p "$t/App.xcodeproj"
js="$("$INSTALL" audit "$t" --no-install-check --json 2>&1)"
python3 -c "import json,sys; assert json.loads(sys.argv[1])['kind']=='app'" "$js" 2>/dev/null && PASS=$((PASS + 1)) \
    || { red "FAIL: a repo with an .xcodeproj should audit as an app"; FAIL=$((FAIL + 1)); }
rm -rf "$t"

finish
