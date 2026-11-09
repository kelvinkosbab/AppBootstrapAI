"""Unit tests for lib/audit.py checks.

Run with: python3 -m unittest discover -s tests

Every line check in audit.CHECKS needs a positive and a negative sample in
SAMPLES, so a new check can't land without showing what it catches and what
it leaves alone.
"""

import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

import audit  # noqa: E402

# check id -> (line that must match, similar line that must not)
SAMPLES = {
    "swift-unchecked-sendable": ("final class Box: @unchecked Sendable {}", "final class Box: Sendable {}"),
    "swift-force-try": ("let x = try! load()", "let x = try load()"),
    "swift-uiscreen-main": ("let w = UIScreen.main.bounds.width", "let w = window.screen.bounds.width"),
    "swift-idiom-layout": ("if traitCollection.userInterfaceIdiom == .pad {", "if horizontalSizeClass == .regular {"),
    "swift-orientation-layout": ("if UIDevice.current.orientation.isLandscape {", "if size.width > size.height {"),
    "swift-hinge-force-unwrap": ("let h = posture.hinge!", "if let h = posture.hinge {"),
    "swift-symmetric-safe-area": ("let pad = safeAreaInsets.left * 2", "let pad = safeAreaInsets.left + safeAreaInsets.right"),
    "swift-dispatch-main": ("DispatchQueue.main.async { reload() }", "Task { @MainActor in reload() }"),
    "swift-print": ("    print(\"loaded\")", "    logger.debug(\"loaded\")"),
    "swift-fixed-font": (".font(.system(size: 17))", ".font(.body)"),
    "swift-raw-symbol": ("Image(systemName: \"star\")", "Image(symbol: .star)"),
    "swift-literal-color": ("let c = Color(red: 1, green: 0, blue: 0)", "let c = Color.accentColor"),
    "swift-text-literal": ("Text(\"Save changes\")", "Text(Strings.save)"),
    "swift-mouse-override": ("override func mouseDown(with event: NSEvent) {", "override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) {"),
    "swift-tracking-loop": ("let e = window.nextEvent(matching: .leftMouseUp)", "let e = gesture.location(in: view)"),
    "swift-timer-retains-self": (
        "Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)",
        "Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }"),
    "swift-assign-on-self": (".assign(to: \\.title, on: self)", ".assign(to: &$title)"),
    "swift-strong-delegate": ("    var delegate: MyDelegate?", "    weak var delegate: MyDelegate?"),
    "swift-full-image-decode": ("let img = UIImage(data: data)", "let img = downsample(data, to: size)"),
    "swift-secret-in-defaults": ("UserDefaults.standard.set(t, forKey: \"authToken\")", "UserDefaults.standard.set(t, forKey: \"theme\")"),
    "swift-cache-in-documents": ("let url = URL.documentsDirectory.appending(path: \"cache\")", "let url = URL.cachesDirectory.appending(path: \"cache\")"),
    "swift-open-app-when-run": ("static var openAppWhenRun = true", "static var supportedModes: IntentModes = .foreground"),
    "swift-assistant-schema-macro": ("@AssistantIntent(schema: .photos.search)", "@AppIntent(schema: .photos.search)"),
    "xcconfig-pointer-auth-off": ("ENABLE_POINTER_AUTHENTICATION = NO", "ENABLE_POINTER_AUTHENTICATION = YES"),
    "xcconfig-enhanced-security-off": ("ENABLE_ENHANCED_SECURITY = NO", "ENABLE_ENHANCED_SECURITY = YES"),
    "kt-global-scope": ("GlobalScope.launch { sync() }", "viewModelScope.launch { sync() }"),
    "kt-run-blocking": ("runBlocking { load() }", "coroutineScope { load() }"),
    "kt-collect-as-state": ("val s by flow.collectAsState()", "val s by flow.collectAsStateWithLifecycle()"),
    "kt-android-log": ("Log.d(TAG, \"x\")", "Timber.d(\"x\")"),
    "kt-announce": ("view.announceForAccessibility(msg)", "view.contentDescription = msg"),
    "kt-literal-color": ("val c = Color(0xFF6200EE)", "val c = MaterialTheme.colorScheme.primary"),
    "kt-empty-content-description": ("Icon(Icons.Default.Star, contentDescription = \"\")", "Icon(Icons.Default.Star, contentDescription = null)"),
    "kt-kapt": ("kapt(libs.room.compiler)", "ksp(libs.room.compiler)"),
    "kt-icons-extended": ("implementation(\"androidx.compose.material:material-icons-extended\")", "implementation(\"androidx.compose.material:material-icons-core\")"),
    "kt-requested-orientation": ("requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT", "val o = resources.configuration.orientation"),
    "kt-device-heuristic": ("if (isTablet) twoPane()", "if (widthClass.isAtLeastBreakpoint(840)) twoPane()"),
    "kt-window-size-class-v1": ("when (WindowWidthSizeClass.COMPACT) {", "when (windowSizeClass.minWidthDp) {"),
    "kt-display-metrics": ("val w = resources.displayMetrics.widthPixels", "val w = LocalWindowInfo.current.containerSize.width"),
    "kt-static-field-leak": ("@SuppressLint(\"StaticFieldLeak\")", "@SuppressLint(\"NewApi\")"),
    "kt-viewmodel-holds-ui": (
        "class HomeViewModel(private val activity: MainActivity) : ViewModel() {",
        "class HomeViewModel(private val repo: Repo) : ViewModel() {"),
    "kt-large-heap": ("<application android:largeHeap=\"true\">", "<application android:largeHeap=\"false\">"),
    "kt-full-bitmap-decode": ("BitmapFactory.decodeFile(path)", "imageLoader.enqueue(request)"),
    "kt-prefs-commit": ("prefs.edit().putInt(\"k\", 1).commit()", "prefs.edit { putInt(\"k\", 1) }"),
    "kt-secret-in-prefs": ("putString(\"apiKey\", key)", "putString(\"theme\", key)"),
    "kt-security-crypto": ("val p = EncryptedSharedPreferences.create(ctx, f, k, s, v)", "val p = dataStore.data"),
    "kt-external-storage-path": ("val d = Environment.getExternalStorageDirectory()", "val d = context.getExternalFilesDir(null)"),
    "kt-main-thread-queries": (".allowMainThreadQueries()", ".fallbackToDestructiveMigration()"),
    "hardcoded-secret": ("let key = \"sk-ant-api03-abcdefghijklmnopqrstuvwx\"", "let key = ProcessInfo.processInfo.environment[\"API_KEY\"]"),
    "ai-brand-in-ui": ("Text(\"Ask Claude\")", "Text(\"Ask the assistant\")"),
}


class LineCheckSamples(unittest.TestCase):
    def test_every_check_has_samples(self):
        missing = sorted({c.id for c in audit.CHECKS} - set(SAMPLES))
        self.assertEqual(missing, [], "add a positive and negative sample for each new check")

    def test_positive_and_negative_samples(self):
        for c in audit.CHECKS:
            positive, negative = SAMPLES[c.id]
            with self.subTest(check=c.id):
                self.assertTrue(c.pattern.search(positive), f"{c.id} should match: {positive}")
                self.assertFalse(c.pattern.search(negative), f"{c.id} should not match: {negative}")


def write(root, rel, text=""):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)
    return path


class ScanBehaviour(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def scan(self):
        findings = {}
        facts = audit.scan_sources(self.root, {"apple"}, findings)
        return findings, facts

    def test_comment_lines_are_skipped(self):
        write(self.root, "Sources/A.swift", "// try! is banned here\n/* DispatchQueue.main.async */\n")
        findings, _ = self.scan()
        self.assertNotIn("swift-force-try", findings)
        self.assertNotIn("swift-dispatch-main", findings)

    def test_skip_tests_checks_ignore_test_files(self):
        write(self.root, "Tests/ATests.swift", "let x = try! load()\n")
        findings, _ = self.scan()
        self.assertNotIn("swift-force-try", findings)

    def test_swiftui_app_and_uikit_delegate_are_detected_in_swift(self):
        write(self.root, "App/MyApp.swift", "@main\nstruct MyApp: App {\n}\n")
        write(self.root, "App/Delegate.swift", "class AppDelegate: NSObject, UIApplicationDelegate {}\n")
        _, facts = self.scan()
        self.assertTrue(facts["swiftui_app"])
        self.assertTrue(facts["uikit_delegate"])


class PackageManifestChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def run_checks(self, kind):
        findings = {}
        facts = audit.scan_sources(self.root, {"apple"}, findings)

        def add(id_, title, sev, rule, skill, fix, loc):
            findings.setdefault(id_, audit.Finding(id_, title, sev, rule, skill, fix)).add(loc)

        audit._spm_checks(self.root, facts, add, kind)
        return findings

    GOOD = """// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Lib",
    platforms: [.iOS(.v17)],
    dependencies: [.package(url: "https://example.com/x", from: "1.0.0")],
    targets: [.target(name: "Lib", swiftSettings: [.swiftLanguageMode(.v6)])]
)
"""

    def test_clean_manifest_has_no_findings(self):
        write(self.root, "Package.swift", self.GOOD)
        self.assertEqual(sorted(self.run_checks("package")), [])

    def test_library_manifest_problems(self):
        write(self.root, "Package.swift", """// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Lib",
    dependencies: [
        .package(path: "../Other"),
        .package(url: "https://example.com/y", branch: "main"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.63.2"),
    ],
    targets: [.target(name: "Lib",
        swiftSettings: [.unsafeFlags(["-warnings-as-errors"])],
        plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")])]
)
""")
        found = set(self.run_checks("package"))
        self.assertTrue({"spm-no-language-mode", "spm-no-platforms", "spm-unsafe-flags",
                         "spm-unpinned-dependency", "spm-lint-plugin-inherited"} <= found, found)

    def test_app_local_package_may_use_unsafe_flags_and_paths(self):
        write(self.root, "Pkgs/Package.swift", self.GOOD.replace(
            'from: "1.0.0")', 'from: "1.0.0"), .package(path: "../Sibling")').replace(
            "[.swiftLanguageMode(.v6)]", '[.swiftLanguageMode(.v6), .unsafeFlags(["-Onone"])]'))
        found = set(self.run_checks("app"))
        self.assertNotIn("spm-unsafe-flags", found)
        self.assertNotIn("spm-unpinned-dependency", found)

    def test_commented_settings_do_not_count(self):
        write(self.root, "Package.swift", self.GOOD.replace(
            "    platforms: [.iOS(.v17)],\n", "    // platforms: [.iOS(.v17)],\n"))
        self.assertIn("spm-no-platforms", self.run_checks("package"))

    def test_ld_classic_in_xcconfig(self):
        write(self.root, "Package.swift", self.GOOD)
        write(self.root, "Config/Base.xcconfig", "OTHER_LDFLAGS = -ld_classic\n")
        self.assertIn("build-ld-classic", self.run_checks("package"))

    def test_implementation_only_with_internal_imports(self):
        write(self.root, "Package.swift", self.GOOD.replace(
            "[.swiftLanguageMode(.v6)]", '[.swiftLanguageMode(.v6), .enableUpcomingFeature("InternalImportsByDefault")]'))
        write(self.root, "Sources/Lib/A.swift", "@_implementationOnly import Foundation\n")
        self.assertIn("spm-implementation-only", self.run_checks("package"))

    def test_app_ignoring_package_resolved(self):
        write(self.root, "Package.swift", self.GOOD)
        write(self.root, ".gitignore", ".build/\nPackage.resolved\n")
        self.assertIn("spm-app-resolved-ignored", self.run_checks("app"))
        self.assertNotIn("spm-app-resolved-ignored", self.run_checks("package"))

    def test_library_tracking_package_resolved(self):
        write(self.root, "Package.swift", self.GOOD)
        write(self.root, "Package.resolved", "{}")
        try:
            subprocess.run(["git", "init", "-q", self.root], check=True)
            subprocess.run(["git", "-C", self.root, "add", "Package.resolved"], check=True)
        except (OSError, subprocess.CalledProcessError):
            self.skipTest("git not available")
        self.assertIn("spm-library-resolved-tracked", self.run_checks("package"))


class ProjectKind(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def test_plain_package(self):
        write(self.root, "Package.swift")
        self.assertEqual(audit.project_kind(self.root), "package")

    def test_package_with_example_app_is_still_a_package(self):
        write(self.root, "Package.swift")
        write(self.root, "Example/Example.xcodeproj/project.pbxproj")
        write(self.root, "Demo/Demo.xcworkspace/contents.xcworkspacedata")
        self.assertEqual(audit.project_kind(self.root), "package")

    def test_app_with_local_package(self):
        write(self.root, "MyApp.xcodeproj/project.pbxproj")
        write(self.root, "MyAppPackages/Package.swift")
        self.assertEqual(audit.project_kind(self.root), "app")

    def test_root_package_with_root_app_project_is_an_app(self):
        write(self.root, "Package.swift")
        write(self.root, "MyApp.xcodeproj/project.pbxproj")
        self.assertEqual(audit.project_kind(self.root), "app")


if __name__ == "__main__":
    unittest.main()
