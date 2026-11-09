/**
 * AppBootstrapAI MCP server: the tools and prompts, built on the SDK's
 * McpServer with zod input schemas. index.ts connects it to stdio; the tests
 * connect it to an in-memory client.
 *
 * Tools:
 *   - recommend_setup     Analyze a directory and return the recommended action
 *                         (create / adopt / upgrade) as JSON with a ready-to-run
 *                         command[]. The agent's entry point: call it first.
 *   - list_categories     Return the feature categories with descriptions. The
 *                         set is read live from `install.sh --list --json`, so
 *                         it never drifts from what the installer recognizes.
 *   - list_rules          Return every rule's frontmatter (description, globs, file path).
 *   - list_skills         Return every skill's frontmatter + its reference files.
 *   - preview_install     Run `install.sh --list` for a given selection; return parsed catalog.
 *   - install             Run `install.sh install` against a target directory (supports
 *                         --agents and --with-mcps).
 *   - preview_upgrade     Run `install.sh upgrade <dir>` (plan-only, writes nothing).
 *   - preview_uninstall   Run `install.sh uninstall <dir> --dry-run` (plan-only).
 *   - uninstall           Run `install.sh uninstall <dir>` (destructive: preview first).
 *   - audit_project       Run `install.sh audit <dir> --json`: install freshness plus
 *                         rule-violation hotspots, each mapped to a rule and a skill,
 *                         plus checks on the repo's own AI steering files.
 *
 * Prompts:
 *   - sync_and_audit      The end-to-end agent workflow (playbooks/sync-and-audit.md).
 *   - audit               Audit only, no install (playbooks/audit.md).
 *
 * A failing tool returns a result with isError: true and the message, which is
 * what McpServer does with any error a handler throws.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { readFile, readdir, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { z } from "zod";

// --- Locate the AppBootstrapAI repo root --------------------------------------
//
// First match wins:
//   1. $APPBOOTSTRAP_BUNDLE: an explicit checkout.
//   2. <repo>/mcp-server/dist/server.js → <repo>, when run from a clone.
//   3. <pkg>/bundle: the copy `npm pack` bundles (scripts/pack-bundle.mjs),
//      so `npx @kelvinkosbab/appbootstrap-mcp` works with no clone.

const here = dirname(fileURLToPath(import.meta.url));

/** The package version, reported to clients in the MCP handshake. */
export const SERVER_VERSION: string = JSON.parse(readFileSync(join(here, "..", "package.json"), "utf-8")).version;

export function findBundleRoot(): string {
    return [
        process.env.APPBOOTSTRAP_BUNDLE,
        resolve(here, "..", ".."),
        resolve(here, "..", "bundle"),
    ].find((p): p is string => !!p && existsSync(join(p, "install.sh"))) ?? resolve(here, "..", "..");
}

// --- Category metadata --------------------------------------------------------
//
// The authoritative SET of categories, and which ones are in the `recommended`
// preset, is read at startup from `install.sh --list --json` (loadCategories).
// This map supplies only prose descriptions. A category present in install.sh
// but missing here gets an empty description; it never disappears from the set.
const CATEGORY_DESCRIPTIONS: Record<string, string> = {
    core:             "Project-level README/CHANGELOG/CONTRIBUTING/ADR patterns, plus cross-platform (Apple + Android) steering when platform is both.",
    concurrency:      "Swift 6.2 strict concurrency / Kotlin coroutines structured concurrency.",
    ui:               "SwiftUI/MVVM / Jetpack Compose patterns + accessibility, design system, iconography, and motion design.",
    testing:          "Test strategy + coverage gates (Apple + Android).",
    docs:             "DocC / KDoc documentation strategy.",
    "error-handling": "Swift typed throws / Result / LocalizedError.",
    packaging:        "Package.swift / Gradle authoring and modular app structure (local SPM package, multi-module Gradle).",
    logging:          "os.Logger discipline (privacy markers, subsystem/category).",
    localization:     "String Catalogs / strings.xml / plurals / RTL.",
    linting:          "SwiftLint + formatter (Apple) / ktlint + detekt + Android Lint (Android): config, suppression hygiene, baselines, triage decision-order, CI placement.",
    compliance:       "Region-specific App Store / Play rules: storefront availability, China ICP and generative-AI filings, third-party AI brand mentions, EU trader status, storefront-based gating, regional rejections.",
    "memory-storage": "Memory and on-device storage (Apple + Android): retain cycles and Context leaks, image decode size, bounded caches, memory pressure, storage locations, backup rules, secrets, free space, app size.",
    performance:      "Profiling with Instruments / xctrace: recording and reading traces, call trees, symbolication, hang triage.",
    persistence:      "Core Data under Swift 6 strict concurrency.",
    ai:               "In-app AI models: Apple Foundation Models (iOS 26+) + Android Gemini Nano / ML Kit GenAI / Firebase AI Logic.",
    migration:        "Android XML/Fragment → Compose migration.",
    shrinking:        "R8 / ProGuard configuration and keep-rule discipline.",
    spatial:          "visionOS: scene types, immersion styles, spatial gestures, RealityKit/ECS, USDZ pipeline.",
    deployment:       "TestFlight (Apple) + Play beta tracks (Android): versioning, signing, CI patterns, gotchas.",
    architecture:     "Android MVVM/UDF (StateFlow UiState, SavedStateHandle, Route/Screen) + repository pattern / data layer (Apple + Android).",
    intents:          "App Intents, App Shortcuts, and Siri tools (27.3): perform() isolation, stable entities, phrases, schemas, AppIntentsTesting, SiriEvaluations.",
    security:         "Xcode build security: security warnings and analyzer checks, Enhanced Security, hardened-process entitlements, phased rollout, C bounds safety.",
};

export interface Category { name: string; recommended: boolean; description: string; }

// --- Helpers ------------------------------------------------------------------

function frontmatter(content: string): string | null {
    if (!content.startsWith("---\n")) return null;
    const end = content.indexOf("\n---\n", 4);
    return end < 0 ? null : content.slice(4, end);
}

/** Parse the `description:` line from a YAML frontmatter block. Best-effort. */
function extractDescription(content: string): string | null {
    const match = frontmatter(content)?.match(/^description:\s*(.*)$/m);
    return match ? match[1].trim() : null;
}

/** Parse the `globs:` line from a YAML frontmatter block. */
function extractGlobs(content: string): string | null {
    const match = frontmatter(content)?.match(/^globs:\s*"?([^"\n]*)"?$/m);
    return match ? match[1].trim() : null;
}

/** Run a command and capture stdout/stderr/exit code. */
function runCommand(cmd: string, args: string[]): Promise<{ stdout: string; stderr: string; code: number }> {
    return new Promise((resolveP, rejectP) => {
        const child = spawn(cmd, args, { env: process.env });
        let stdout = "";
        let stderr = "";
        child.stdout.on("data", (chunk) => { stdout += chunk.toString(); });
        child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
        child.on("error", rejectP);
        child.on("close", (code) => resolveP({ stdout, stderr, code: code ?? -1 }));
    });
}

const text = (t: string) => ({ content: [{ type: "text" as const, text: t }] });
const json = (v: unknown) => text(JSON.stringify(v, null, 2));

function failure(what: string, r: { code: number; stdout: string; stderr: string }): Error {
    return new Error(`${what} exited with code ${r.code}.\n\nstderr:\n${r.stderr}\n\nstdout:\n${r.stdout}`);
}

/**
 * Read the category set from `install.sh --list --json` and merge in the prose
 * descriptions, so the server can't drift from the installer's taxonomy.
 */
export async function loadCategories(installSh: string): Promise<Category[]> {
    const result = await runCommand("bash", [installSh, "--list", "--json", "--platform", "both", "--features", "all"]);
    if (result.code !== 0) {
        throw new Error(`install.sh --list --json failed (code ${result.code}): ${result.stderr}`);
    }
    const parsed = JSON.parse(result.stdout);
    if (!Array.isArray(parsed.categories)) {
        throw new Error("install.sh --list --json did not return a 'categories' array. Is install.sh up to date with the MCP server?");
    }
    return parsed.categories.map((c: { name: string; recommended: boolean }) => ({
        name: c.name,
        recommended: c.recommended,
        description: CATEGORY_DESCRIPTIONS[c.name] ?? "",
    }));
}

// --- Input schemas ------------------------------------------------------------

// Absolute only: a relative value like "audit" or "upgrade" would be read by
// install.sh as a command verb, and one starting with "-" as a flag.
const targetDir = (description: string) => z.string()
    .refine(isAbsolute, { message: "target_dir must be an absolute path" })
    .describe(description);

const platform = z.enum(["apple", "android", "both"]);
const appleLanguage = z.enum(["swift", "objc", "both"])
    .describe("Default: swift. Only relevant when platform includes apple.");
const applePlatforms = z.string().describe("Comma-separated Apple sub-platforms (ios, macos, tvos, watchos, visionos) or 'all'. Default: ios,macos,tvos,watchos (no visionOS). Naming 'visionos' adds the visionOS rule; 'macos' gates the touch-on-Mac rule (apple-mac-touch.md). Only relevant when platform includes apple.");
const androidPlatforms = z.string().describe("Comma-separated Android form factors (phone, tablet, wear, tv, auto) or 'all'. Default: phone,tablet. 'tablet' gates the large-screen / foldable rule (android-large-screen-best-practices.md) and the android-adaptive-layout-pro skill; other tokens are recorded in the manifest for future form-factor rules. Only relevant when platform includes android.");
const features = z.string().describe("Comma-separated category list, or one of: 'recommended' (default), 'all'.");

// --- Server -------------------------------------------------------------------

export interface ServerOptions {
    /** The AppBootstrapAI checkout to run. Defaults to findBundleRoot(). */
    bundleRoot?: string;
}

export async function createServer(options: ServerOptions = {}): Promise<{ server: McpServer; categories: Category[]; bundleRoot: string }> {
    const root = options.bundleRoot ?? findBundleRoot();
    const installSh = join(root, "install.sh");
    const rulesDir = join(root, ".claude", "rules");
    const skillsDir = join(root, ".claude", "skills");
    const categories = await loadCategories(installSh);
    const run = (args: string[]) => runCommand("bash", [installSh, ...args]);

    /** Validate a feature CSV against the category set install.sh reported. */
    function checkFeatures(input: string): void {
        if (input === "all" || input === "recommended") return;
        const known = new Set(categories.map(c => c.name));
        for (const f of input.split(",").map(s => s.trim()).filter(Boolean)) {
            if (!known.has(f)) {
                throw new Error(`Unknown feature category: "${f}". Valid: ${[...known].join(", ")}. Presets: all, recommended.`);
            }
        }
    }

    async function runJson(what: string, args: string[]) {
        const r = await run(args);
        if (r.code !== 0) throw failure(what, r);
        try {
            return json(JSON.parse(r.stdout));
        } catch {
            throw new Error(`${what} did not return JSON:\n${r.stdout}`);
        }
    }

    async function uninstall(a: { target_dir: string; dry_run?: boolean; purge?: boolean; keep_mcps?: boolean; force_conflicts?: boolean }) {
        const args = ["uninstall", a.target_dir];
        if (a.dry_run) args.push("--dry-run");
        if (a.purge) args.push("--purge");
        if (a.keep_mcps) args.push("--keep-mcps");
        if (a.force_conflicts) args.push("--force-conflicts");
        const r = await run(args);
        if (r.code !== 0) throw failure("install.sh uninstall", r);
        return json({
            exit_code: r.code,
            target_dir: a.target_dir,
            dry_run: !!a.dry_run,
            purge: !!a.purge,
            keep_mcps: !!a.keep_mcps,
            force_conflicts: !!a.force_conflicts,
            stdout: r.stdout,
            stderr: r.stderr,
        });
    }

    const server = new McpServer({ name: "appbootstrap", version: SERVER_VERSION });
    const readOnly = { readOnlyHint: true, openWorldHint: false };

    server.registerTool("recommend_setup", {
        description: "Analyze a directory and return the recommended AppBootstrapAI action as structured JSON. CALL THIS FIRST when asked to set up / update / improve a repo — it tells you exactly what to run. Detects managed-state (manifest → upgrade), platform, Apple-language, and framework usage (FoundationModels→ai, Core Data/SwiftData→persistence, Room→persistence, R8/ProGuard→shrinking, XML layouts/Fragments→migration, fastlane/CI→deployment). Returns { state, platform, apple_language, features, action, feature_reasons, command[], preview_command[] }. Read-only — writes nothing. Then run preview (command + --dry-run) and confirm before calling `install`.",
        inputSchema: { target_dir: targetDir("Absolute path to the directory to analyze. Required.") },
        annotations: readOnly,
    }, async ({ target_dir }) => runJson("install.sh recommend", ["recommend", target_dir, "--json"]));

    server.registerTool("list_categories", {
        description: "List the feature categories AppBootstrapAI's install.sh recognizes. Returns name + recommended flag + description for each. The set is read live from install.sh so it never drifts. `recommended: true` categories install by default; the rest are opt-in via --features.",
        annotations: readOnly,
    }, async () => json({ categories }));

    server.registerTool("list_rules", {
        description: "List every steering rule in .claude/rules/ with its description and globs. Useful for the agent to understand what each rule covers before recommending which categories to install.",
        annotations: readOnly,
    }, async () => {
        const files = (await readdir(rulesDir)).filter(f => f.endsWith(".md")).sort();
        const rules = await Promise.all(files.map(async (filename) => {
            const content = await readFile(join(rulesDir, filename), "utf-8");
            return { filename, description: extractDescription(content), globs: extractGlobs(content) };
        }));
        return json({ rules });
    });

    server.registerTool("list_skills", {
        description: "List every skill in .claude/skills/ with its description and reference file names. Skills are on-demand review agents; rules are always-loaded steering files.",
        annotations: readOnly,
    }, async () => {
        const dirs = (await readdir(skillsDir)).sort();
        const skills = await Promise.all(dirs.map(async (name) => {
            const skillPath = join(skillsDir, name);
            if (!(await stat(skillPath).catch(() => null))?.isDirectory()) return null;
            const content = await readFile(join(skillPath, "SKILL.md"), "utf-8").catch(() => "");
            const references = await readdir(join(skillPath, "references")).catch(() => [] as string[]);
            return {
                name,
                description: extractDescription(content),
                references: references.filter(r => r.endsWith(".md")).sort(),
            };
        }));
        return json({ skills: skills.filter(s => s !== null) });
    });

    server.registerTool("preview_install", {
        description: "Preview what `install.sh` would install for a given platform/language/features combination. Returns the install.sh --list output verbatim (catalog with [✓]/[ ] marks per file). No files written. Use this before calling `install` so the user can confirm the selection.",
        inputSchema: {
            platform: platform.default("both").describe("Default: both"),
            apple_language: appleLanguage.default("swift"),
            apple_platforms: applePlatforms.optional(),
            android_platforms: androidPlatforms.optional(),
            features: features.default("recommended"),
        },
        annotations: readOnly,
    }, async (a) => {
        checkFeatures(a.features);
        const args = ["--list", "--platform", a.platform, "--apple-language", a.apple_language, "--features", a.features];
        if (a.apple_platforms) args.push("--apple-platforms", a.apple_platforms);
        if (a.android_platforms) args.push("--android-platforms", a.android_platforms);
        const r = await run(args);
        if (r.code !== 0) throw failure("install.sh --list", r);
        return text(r.stdout);
    });

    server.registerTool("install", {
        description: "Run AppBootstrapAI's installer against a target directory. Copies skills, rules, settings.json, CLAUDE.md template, and .gitignore entries matching the selection. With --agents, also writes per-agent files (.github/copilot-instructions.md, .cursor/rules/*.mdc, GEMINI.md, AGENTS.md, .kiro/steering/*.md, .agents/skills/ + .aiexclude for Android Studio). Never overwrites existing CLAUDE.md/settings.json/agent files (prints what was skipped). Returns install.sh's stdout/stderr + exit code.",
        inputSchema: {
            target_dir: targetDir("Absolute path to the directory where AppBootstrapAI should be installed. Required."),
            platform: platform.optional().describe("Default: auto-detected from target_dir"),
            apple_language: appleLanguage.default("swift"),
            apple_platforms: applePlatforms.optional(),
            android_platforms: androidPlatforms.optional(),
            features: features.default("recommended"),
            agents: z.string().optional().describe("Comma-separated AI agents to install for: claude (default), copilot, cursor, gemini, codex, kiro, android-studio, or 'all'. Additive."),
            with_mcps: z.string().optional().describe("Comma-separated MCP recipe names to add to .claude/settings.local.json (e.g. 'xcodebuildmcp,sentry'). See list-mcps in the bundle for available recipes."),
        },
        annotations: { destructiveHint: false, idempotentHint: true, openWorldHint: false },
    }, async (a) => {
        checkFeatures(a.features);
        // No platform → install.sh auto-detects it from target_dir, the same as
        // a shell install. Optional flags are only passed when given.
        const args = ["install", a.target_dir, "--apple-language", a.apple_language, "--features", a.features];
        if (a.platform) args.push("--platform", a.platform);
        if (a.apple_platforms) args.push("--apple-platforms", a.apple_platforms);
        if (a.android_platforms) args.push("--android-platforms", a.android_platforms);
        if (a.agents) args.push("--agents", a.agents);
        if (a.with_mcps) args.push("--with-mcps", a.with_mcps);
        const r = await run(args);
        if (r.code !== 0) throw failure("install.sh install", r);
        return json({
            exit_code: r.code,
            target_dir: a.target_dir,
            platform: a.platform ?? "auto-detected (see stdout)",
            apple_language: a.apple_language,
            apple_platforms: a.apple_platforms ?? "ios,macos,tvos,watchos (default)",
            features: a.features,
            agents: a.agents ?? "claude",
            with_mcps: a.with_mcps ?? null,
            stdout: r.stdout,
            stderr: r.stderr,
        });
    });

    server.registerTool("preview_upgrade", {
        description: "Run `install.sh <target_dir> --upgrade` — a plan-only diff of what would change if the target re-installed from the current bundle. Writes NOTHING. Classifies each tracked file as up-to-date / safe-update / locally-edited / conflict / orphan / addition / rename, and surfaces a GitHub compare URL when the bundle commit differs. Use before deciding whether to re-run `install`.",
        inputSchema: {
            target_dir: targetDir("Absolute path to an existing AppBootstrapAI install (must contain .claude/.appbootstrap-manifest.json). Required."),
            features: z.string().optional().describe("Optional. Opt into new categories at upgrade time (e.g. 'recommended,spatial'). Defaults to whatever the manifest recorded."),
        },
        annotations: readOnly,
    }, async (a) => {
        // Plan-only: `upgrade` without `--apply` never writes. Selection flags
        // default from the manifest, so --features is forwarded only when given.
        const args = ["upgrade", a.target_dir];
        if (a.features) {
            checkFeatures(a.features);
            args.push("--features", a.features);
        }
        const r = await run(args);
        if (r.code !== 0) throw failure("install.sh upgrade", r);
        return text(r.stdout);
    });

    server.registerTool("audit_project", {
        description: "Audit a repo against the AppBootstrapAI bundle. Read-only. Returns { mode (new|existing), install {state, up_to_date, command[], preview_command[]}, summary, findings[], skills_to_run[], steering }. Each finding has severity, file:line locations, a one-line fix, and the rule_path / skill_path to read for a deep review. Findings accepted in the repo's audit baseline (.claude/appbootstrap-audit-baseline.json) are listed under baseline.suppressed instead; pass no_baseline to see everything. Pass skip_install_check when auditing a repo the user doesn't want the bundle installed into. kind is package (a library) or app. steering inventories the repo's AI steering files (CLAUDE.md, AGENTS.md, Cursor / Copilot / Kiro rules, skills) with the agent, load kind, size, and owner of each; steering-* findings flag stale paths and commands, placeholders, secrets, oversized or duplicated files, and lines that contradict a bundle rule. Pass steering_only to audit just those files. Findings are regex/file-presence hotspots: confirm or dismiss each by reading the code and the rule. Follow the audit prompt (audit only) or sync_and_audit prompt (install + audit) for the full workflow.",
        inputSchema: {
            target_dir: targetDir("Absolute path to the repo to audit. Required."),
            no_baseline: z.boolean().optional().describe("Ignore the audit baseline and report every finding."),
            skip_install_check: z.boolean().optional().describe("Audit without the bundle installed: drop the not-installed / outdated findings."),
            steering_only: z.boolean().optional().describe("Audit only the repo's AI steering files; skip the code checks and deep reviews."),
        },
        annotations: readOnly,
    }, async (a) => {
        const args = ["audit", a.target_dir, "--json"];
        if (a.no_baseline) args.push("--no-baseline");
        if (a.skip_install_check) args.push("--no-install-check");
        if (a.steering_only) args.push("--steering-only");
        return runJson("install.sh audit", args);
    });

    server.registerTool("preview_uninstall", {
        description: "Plan-only `install.sh <target_dir> --uninstall --dry-run`. Lists what an uninstall WOULD delete vs. keep (unchanged tracked files deleted; locally-edited files and CLAUDE.md/settings.json kept) without writing anything. Use before `uninstall`.",
        inputSchema: { target_dir: targetDir("Absolute path to an existing AppBootstrapAI install. Required.") },
        annotations: readOnly,
    }, async ({ target_dir }) => uninstall({ target_dir, dry_run: true }));

    server.registerTool("uninstall", {
        description: "Reverse an AppBootstrapAI install in target_dir. Deletes every tracked file unchanged since install; keeps locally-edited files unless force_conflicts, keeps CLAUDE.md/settings.json unless purge, removes MCP entries unless keep_mcps; strips the .gitignore block + manifest. DESTRUCTIVE — call preview_uninstall first and confirm with the user.",
        inputSchema: {
            target_dir: targetDir("Absolute path to an existing AppBootstrapAI install. Required."),
            purge: z.boolean().optional().describe("Also delete CLAUDE.md and .claude/settings.json. Default false."),
            keep_mcps: z.boolean().optional().describe("Leave settings.local.json MCP entries untouched. Default false."),
            force_conflicts: z.boolean().optional().describe("Also delete locally-edited tracked files. Default false."),
        },
        annotations: { destructiveHint: true, openWorldHint: false },
    }, async (a) => uninstall(a));

    // --- Prompts --------------------------------------------------------------
    //
    // Sourced from the playbook files so the MCP path and the plain "read this
    // Markdown" path never diverge. sync-and-audit.md defers its triage and
    // report steps to audit.md, so both prompts carry it.

    const promptArgs = {
        target_dir: z.string().optional().describe("Absolute path to the repo. Defaults to the current working directory."),
    };

    server.registerPrompt("sync_and_audit", {
        description: "Bring a repo up to the latest AppBootstrapAI bundle, then audit it against the bundle's rules and skills and write a report. Previews before writing; never commits.",
        argsSchema: promptArgs,
    }, async ({ target_dir }) => {
        const target = target_dir || "the current working directory";
        const body = [
            `Run this playbook against ${target}. BUNDLE is ${root}.`,
            "Use the appbootstrap MCP tools where they map to a step: recommend_setup for `recommend`, preview_upgrade / preview_install for the preview, install for adopt, audit_project for `audit`. Use the shell for `upgrade --apply`.",
            "",
            await readFile(join(root, "playbooks", "sync-and-audit.md"), "utf-8"),
            "",
            "---",
            "",
            "audit.md, which steps 2 and 3 above refer to:",
            "",
            await readFile(join(root, "playbooks", "audit.md"), "utf-8"),
        ].join("\n");
        return {
            description: "AppBootstrapAI sync and audit",
            messages: [{ role: "user", content: { type: "text", text: body } }],
        };
    });

    server.registerPrompt("audit", {
        description: "Audit a package, app, or repo against the AppBootstrapAI rules and skills without installing anything. Read-only; reports findings in chat.",
        argsSchema: promptArgs,
    }, async ({ target_dir }) => {
        const target = target_dir || "the current working directory";
        const body = [
            `Run this playbook against ${target}. BUNDLE is ${root}; skip step 1.`,
            "Use the audit_project tool with skip_install_check: true for step 2.",
            "",
            await readFile(join(root, "playbooks", "audit.md"), "utf-8"),
        ].join("\n");
        return {
            description: "AppBootstrapAI audit",
            messages: [{ role: "user", content: { type: "text", text: body } }],
        };
    });

    return { server, categories, bundleRoot: root };
}
