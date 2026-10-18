#!/usr/bin/env node
/**
 * AppBootstrapAI MCP server.
 *
 * Exposes the bundle's install.sh as structured tools that AI agents
 * (Claude Code, Cursor, Gemini CLI, Kiro, Codex) can invoke through MCP
 * rather than parsing shell output.
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
 *   - install             Run `install.sh` against a target directory (supports
 *                         --agents and --with-mcps).
 *   - preview_upgrade     Run `install.sh <dir> --upgrade` (plan-only, writes nothing).
 *   - preview_uninstall   Run `install.sh <dir> --uninstall --dry-run` (plan-only).
 *   - uninstall           Run `install.sh <dir> --uninstall` (destructive — preview first).
 *   - audit_project       Run `install.sh audit <dir> --json`: install freshness plus
 *                         rule-violation hotspots, each mapped to a rule and a skill,
 *                         plus checks on the repo's own AI steering files.
 *
 * Prompts:
 *   - sync_and_audit      The end-to-end agent workflow (playbooks/sync-and-audit.md):
 *                         recommend → preview → apply → audit → deep reviews → report.
 *   - audit               Audit only, no install (playbooks/audit.md).
 *
 * Communicates over stdio (the standard MCP transport for local subprocess servers).
 * Configure a client by pointing at the compiled `dist/index.js`.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
    CallToolRequestSchema,
    GetPromptRequestSchema,
    ListPromptsRequestSchema,
    ListToolsRequestSchema,
    McpError,
    ErrorCode,
    type CallToolRequest,
} from "@modelcontextprotocol/sdk/types.js";
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { readFile, readdir, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

// --- Locate the AppBootstrapAI repo root --------------------------------------
//
// First match wins:
//   1. $APPBOOTSTRAP_BUNDLE — an explicit checkout.
//   2. <repo>/mcp-server/dist/index.js → <repo>, when run from a clone.
//   3. <pkg>/bundle — the copy `npm pack` bundles (scripts/pack-bundle.mjs),
//      so `npx @kelvinkosbab/appbootstrap-mcp` works with no clone.

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const REPO_ROOT = [
    process.env.APPBOOTSTRAP_BUNDLE,
    resolve(__dirname, "..", ".."),
    resolve(__dirname, "..", "bundle"),
].find((p): p is string => !!p && existsSync(join(p, "install.sh"))) ?? resolve(__dirname, "..", "..");
const INSTALL_SH = join(REPO_ROOT, "install.sh");
const RULES_DIR = join(REPO_ROOT, ".claude", "rules");
const SKILLS_DIR = join(REPO_ROOT, ".claude", "skills");
const PLAYBOOK = join(REPO_ROOT, "playbooks", "sync-and-audit.md");
const AUDIT_PLAYBOOK = join(REPO_ROOT, "playbooks", "audit.md");

// --- Category metadata --------------------------------------------------------
//
// The authoritative SET of categories — and which ones are in the `recommended`
// preset — is read at startup from `install.sh --list --json` (see
// loadCategories below). That makes install.sh the single source of truth and
// kills the drift class that used to live here as a hand-maintained array.
//
// This map supplies only PROSE descriptions (presentation). A category present
// in install.sh but missing here just gets an empty description — it can never
// silently disappear from the set.
const CATEGORY_DESCRIPTIONS: Record<string, string> = {
    core:             "Project-level README/CHANGELOG/CONTRIBUTING/ADR patterns, plus cross-platform (Apple + Android) steering when platform is both.",
    concurrency:      "Swift 6.2 strict concurrency / Kotlin coroutines structured concurrency.",
    ui:               "SwiftUI/MVVM / Jetpack Compose patterns + accessibility.",
    testing:          "Test strategy + coverage gates (Apple + Android).",
    docs:             "DocC / KDoc documentation strategy.",
    "error-handling": "Swift typed throws / Result / LocalizedError.",
    packaging:        "Package.swift / Gradle authoring and modular app structure (local SPM package, multi-module Gradle).",
    logging:          "os.Logger discipline (privacy markers, subsystem/category).",
    localization:     "String Catalogs / strings.xml / plurals / RTL.",
    linting:          "SwiftLint + formatter (Apple) / ktlint + detekt + Android Lint (Android): config, suppression hygiene, baselines, triage decision-order, CI placement.",
    compliance:       "Region-specific App Store / Play rules: storefront availability, China ICP and generative-AI filings, third-party AI brand mentions, EU trader status, storefront-based gating, regional rejections.",
    persistence:      "Core Data under Swift 6 strict concurrency.",
    ai:               "In-app AI models: Apple Foundation Models (iOS 26+) + Android Gemini Nano / ML Kit GenAI / Firebase AI Logic.",
    migration:        "Android XML/Fragment → Compose migration.",
    shrinking:        "R8 / ProGuard configuration and keep-rule discipline.",
    spatial:          "visionOS: scene types, immersion styles, spatial gestures, RealityKit/ECS, USDZ pipeline.",
    deployment:       "TestFlight (Apple) + Play beta tracks (Android): versioning, signing, CI patterns, gotchas.",
    architecture:     "Android MVVM/UDF (StateFlow UiState, SavedStateHandle, Route/Screen) + repository pattern / data layer (Apple + Android).",
};

interface Category { name: string; recommended: boolean; description: string; }

// Populated once at startup by loadCategories(). Tool handlers run after the
// server connects, so this is always set by the time they read it.
let CATEGORIES: Category[] = [];

// --- Helpers ------------------------------------------------------------------

/** Parse the `description:` line from a YAML frontmatter block. Best-effort. */
function extractDescription(content: string): string | null {
    if (!content.startsWith("---\n")) return null;
    const end = content.indexOf("\n---\n", 4);
    if (end < 0) return null;
    const frontmatter = content.slice(4, end);
    const match = frontmatter.match(/^description:\s*(.*)$/m);
    return match ? match[1].trim() : null;
}

/** Parse the `globs:` line from a YAML frontmatter block. */
function extractGlobs(content: string): string | null {
    if (!content.startsWith("---\n")) return null;
    const end = content.indexOf("\n---\n", 4);
    if (end < 0) return null;
    const frontmatter = content.slice(4, end);
    const match = frontmatter.match(/^globs:\s*"?([^"\n]*)"?$/m);
    return match ? match[1].trim() : null;
}

/** Validate a feature CSV against the known category list. */
function validateFeatures(input: string): string[] {
    if (input === "all") return CATEGORIES.map(c => c.name);
    if (input === "recommended") return CATEGORIES.filter(c => c.recommended).map(c => c.name);
    const list = input.split(",").map(s => s.trim()).filter(Boolean);
    const known = new Set(CATEGORIES.map(c => c.name));
    for (const f of list) {
        if (!known.has(f)) {
            throw new McpError(
                ErrorCode.InvalidParams,
                `Unknown feature category: "${f}". Valid: ${CATEGORIES.map(c => c.name).join(", ")}. Presets: all, recommended.`
            );
        }
    }
    return list;
}

/** Run a shell command and capture stdout/stderr/exit code. */
function runCommand(cmd: string, args: string[], cwd?: string): Promise<{ stdout: string; stderr: string; code: number }> {
    return new Promise((resolveP, rejectP) => {
        const child = spawn(cmd, args, { cwd, env: process.env });
        let stdout = "";
        let stderr = "";
        child.stdout.on("data", (chunk) => { stdout += chunk.toString(); });
        child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
        child.on("error", rejectP);
        child.on("close", (code) => resolveP({ stdout, stderr, code: code ?? -1 }));
    });
}

/**
 * Read the canonical category set from `install.sh --list --json` and merge in
 * the prose descriptions. Single source of truth — keeps the MCP server from
 * drifting out of sync with the installer's feature taxonomy.
 */
async function loadCategories(): Promise<Category[]> {
    const result = await runCommand(
        "bash",
        [INSTALL_SH, "--list", "--json", "--platform", "both", "--features", "all"]
    );
    if (result.code !== 0) {
        throw new Error(`install.sh --list --json failed (code ${result.code}): ${result.stderr}`);
    }
    const parsed = JSON.parse(result.stdout);
    if (!Array.isArray(parsed.categories)) {
        throw new Error(
            "install.sh --list --json did not return a 'categories' array. " +
            "Is install.sh up to date with the MCP server? (Needs the categories emitter.)"
        );
    }
    return parsed.categories.map((c: { name: string; recommended: boolean }) => ({
        name: c.name,
        recommended: c.recommended,
        description: CATEGORY_DESCRIPTIONS[c.name] ?? "",
    }));
}

// --- Tool implementations -----------------------------------------------------

async function toolListCategories() {
    return {
        content: [{
            type: "text" as const,
            text: JSON.stringify({ categories: CATEGORIES }, null, 2)
        }]
    };
}

async function toolListRules() {
    const files = (await readdir(RULES_DIR)).filter(f => f.endsWith(".md"));
    const rules = await Promise.all(files.sort().map(async (filename) => {
        const path = join(RULES_DIR, filename);
        const content = await readFile(path, "utf-8");
        return {
            filename,
            description: extractDescription(content),
            globs: extractGlobs(content),
        };
    }));
    return { content: [{ type: "text" as const, text: JSON.stringify({ rules }, null, 2) }] };
}

async function toolListSkills() {
    const dirs = await readdir(SKILLS_DIR);
    const skills = await Promise.all(dirs.sort().map(async (name) => {
        const skillPath = join(SKILLS_DIR, name);
        const skillStat = await stat(skillPath).catch(() => null);
        if (!skillStat?.isDirectory()) return null;
        const skillMd = join(skillPath, "SKILL.md");
        const content = await readFile(skillMd, "utf-8").catch(() => "");
        const refsDir = join(skillPath, "references");
        const references = await readdir(refsDir).catch(() => []);
        return {
            name,
            description: extractDescription(content),
            references: references.filter(r => r.endsWith(".md")).sort(),
        };
    }));
    return {
        content: [{
            type: "text" as const,
            text: JSON.stringify({ skills: skills.filter(s => s !== null) }, null, 2)
        }]
    };
}

async function toolPreviewInstall(args: { platform?: string; apple_language?: string; features?: string; apple_platforms?: string; android_platforms?: string }) {
    const platform = args.platform ?? "both";
    const appleLanguage = args.apple_language ?? "swift";
    const features = args.features ?? "recommended";

    // Validate locally before shelling out — clearer error messages.
    if (!["apple", "android", "both"].includes(platform)) {
        throw new McpError(ErrorCode.InvalidParams, `platform must be apple, android, or both (got: ${platform})`);
    }
    if (!["swift", "objc", "both"].includes(appleLanguage)) {
        throw new McpError(ErrorCode.InvalidParams, `apple_language must be swift, objc, or both (got: ${appleLanguage})`);
    }
    validateFeatures(features);

    const baseArgs = [INSTALL_SH, "--list", "--platform", platform, "--apple-language", appleLanguage, "--features", features];
    if (args.apple_platforms) baseArgs.push("--apple-platforms", args.apple_platforms);
    if (args.android_platforms) baseArgs.push("--android-platforms", args.android_platforms);
    const result = await runCommand(
        "bash",
        baseArgs
    );
    if (result.code !== 0) {
        throw new McpError(ErrorCode.InternalError, `install.sh --list exited with code ${result.code}: ${result.stderr}`);
    }
    return { content: [{ type: "text" as const, text: result.stdout }] };
}

async function toolInstall(args: {
    target_dir: string;
    platform?: string;
    apple_language?: string;
    apple_platforms?: string;
    android_platforms?: string;
    features?: string;
    agents?: string;
    with_mcps?: string;
}) {
    if (!args.target_dir) {
        throw new McpError(ErrorCode.InvalidParams, "target_dir is required");
    }

    const platform = args.platform ?? "both";
    const appleLanguage = args.apple_language ?? "swift";
    const features = args.features ?? "recommended";

    if (!["apple", "android", "both"].includes(platform)) {
        throw new McpError(ErrorCode.InvalidParams, `platform must be apple, android, or both`);
    }
    if (!["swift", "objc", "both"].includes(appleLanguage)) {
        throw new McpError(ErrorCode.InvalidParams, `apple_language must be swift, objc, or both`);
    }
    validateFeatures(features);

    // Build args incrementally so optional flags are only passed when provided
    // (install.sh defaults --agents to claude and --with-mcps to empty).
    const installArgs = [
        INSTALL_SH, args.target_dir,
        "--platform", platform,
        "--apple-language", appleLanguage,
        "--features", features,
    ];
    if (args.apple_platforms) installArgs.push("--apple-platforms", args.apple_platforms);
    if (args.android_platforms) installArgs.push("--android-platforms", args.android_platforms);
    if (args.agents) installArgs.push("--agents", args.agents);
    if (args.with_mcps) installArgs.push("--with-mcps", args.with_mcps);

    const result = await runCommand("bash", installArgs);

    const summary = {
        exit_code: result.code,
        target_dir: args.target_dir,
        platform,
        apple_language: appleLanguage,
        apple_platforms: args.apple_platforms ?? "ios,macos,tvos,watchos (default)",
        features,
        agents: args.agents ?? "claude",
        with_mcps: args.with_mcps ?? null,
        stdout: result.stdout,
        stderr: result.stderr,
    };

    if (result.code !== 0) {
        throw new McpError(
            ErrorCode.InternalError,
            `install.sh exited with code ${result.code}.\n\nstderr:\n${result.stderr}\n\nstdout:\n${result.stdout}`
        );
    }

    return { content: [{ type: "text" as const, text: JSON.stringify(summary, null, 2) }] };
}

async function toolPreviewUpgrade(args: { target_dir: string; features?: string }) {
    if (!args.target_dir) {
        throw new McpError(ErrorCode.InvalidParams, "target_dir is required");
    }
    if (args.features) validateFeatures(args.features);

    // Plan-only: `--upgrade` without `--apply` never writes. Selection flags
    // default from the target's manifest, so we only forward --features when
    // the caller explicitly wants to opt into new categories.
    const upgradeArgs = [INSTALL_SH, args.target_dir, "--upgrade"];
    if (args.features) upgradeArgs.push("--features", args.features);

    const result = await runCommand("bash", upgradeArgs);
    if (result.code !== 0) {
        throw new McpError(
            ErrorCode.InternalError,
            `install.sh --upgrade exited with code ${result.code}.\n\nstderr:\n${result.stderr}\n\nstdout:\n${result.stdout}`
        );
    }
    return { content: [{ type: "text" as const, text: result.stdout }] };
}

async function toolRecommend(args: { target_dir: string }) {
    if (!args.target_dir) {
        throw new McpError(ErrorCode.InvalidParams, "target_dir is required");
    }
    // Read-only analysis. Returns the parsed recommendation object so the agent
    // can act on `command` / `preview_command` directly.
    const result = await runCommand("bash", [INSTALL_SH, "recommend", args.target_dir, "--json"]);
    if (result.code !== 0) {
        throw new McpError(
            ErrorCode.InternalError,
            `install.sh recommend exited with code ${result.code}: ${result.stderr}`
        );
    }
    let parsed: unknown;
    try {
        parsed = JSON.parse(result.stdout);
    } catch {
        throw new McpError(ErrorCode.InternalError, `recommend did not return JSON:\n${result.stdout}`);
    }
    return { content: [{ type: "text" as const, text: JSON.stringify(parsed, null, 2) }] };
}

async function toolAudit(args: { target_dir: string; no_baseline?: boolean; skip_install_check?: boolean; steering_only?: boolean }) {
    if (!args.target_dir) {
        throw new McpError(ErrorCode.InvalidParams, "target_dir is required");
    }
    // Read-only. Returns findings with rule/skill paths the agent reads next.
    const cmd = [INSTALL_SH, "audit", args.target_dir, "--json"];
    if (args.no_baseline) cmd.push("--no-baseline");
    if (args.skip_install_check) cmd.push("--no-install-check");
    if (args.steering_only) cmd.push("--steering-only");
    const result = await runCommand("bash", cmd);
    if (result.code !== 0) {
        throw new McpError(
            ErrorCode.InternalError,
            `install.sh audit exited with code ${result.code}: ${result.stderr}`
        );
    }
    let parsed: unknown;
    try {
        parsed = JSON.parse(result.stdout);
    } catch {
        throw new McpError(ErrorCode.InternalError, `audit did not return JSON:\n${result.stdout}`);
    }
    return { content: [{ type: "text" as const, text: JSON.stringify(parsed, null, 2) }] };
}

async function toolUninstall(args: {
    target_dir: string;
    dry_run?: boolean;
    purge?: boolean;
    keep_mcps?: boolean;
    force_conflicts?: boolean;
}) {
    if (!args.target_dir) {
        throw new McpError(ErrorCode.InvalidParams, "target_dir is required");
    }
    const uninstallArgs = [INSTALL_SH, args.target_dir, "--uninstall"];
    if (args.dry_run) uninstallArgs.push("--dry-run");
    if (args.purge) uninstallArgs.push("--purge");
    if (args.keep_mcps) uninstallArgs.push("--keep-mcps");
    if (args.force_conflicts) uninstallArgs.push("--force-conflicts");

    const result = await runCommand("bash", uninstallArgs);
    const summary = {
        exit_code: result.code,
        target_dir: args.target_dir,
        dry_run: !!args.dry_run,
        purge: !!args.purge,
        keep_mcps: !!args.keep_mcps,
        force_conflicts: !!args.force_conflicts,
        stdout: result.stdout,
        stderr: result.stderr,
    };
    if (result.code !== 0) {
        throw new McpError(
            ErrorCode.InternalError,
            `install.sh --uninstall exited with code ${result.code}.\n\nstderr:\n${result.stderr}\n\nstdout:\n${result.stdout}`
        );
    }
    return { content: [{ type: "text" as const, text: JSON.stringify(summary, null, 2) }] };
}

// --- MCP wiring ---------------------------------------------------------------

const server = new Server(
    {
        name: "appbootstrap",
        version: "0.1.0",
    },
    {
        capabilities: { tools: {}, prompts: {} },
    }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [
        {
            name: "recommend_setup",
            description: "Analyze a directory and return the recommended AppBootstrapAI action as structured JSON. CALL THIS FIRST when asked to set up / update / improve a repo — it tells you exactly what to run. Detects managed-state (manifest → upgrade), platform, Apple-language, and framework usage (FoundationModels→ai, Core Data/SwiftData→persistence, Room→persistence, R8/ProGuard→shrinking, XML layouts/Fragments→migration, fastlane/CI→deployment). Returns { state, platform, apple_language, features, action, feature_reasons, command[], preview_command[] }. Read-only — writes nothing. Then run preview (command + --dry-run) and confirm before calling `install`.",
            inputSchema: {
                type: "object",
                properties: {
                    target_dir: { type: "string", description: "Absolute path to the directory to analyze. Required." },
                },
                required: ["target_dir"],
                additionalProperties: false
            }
        },
        {
            name: "list_categories",
            description: "List the feature categories AppBootstrapAI's install.sh recognizes. Returns name + recommended flag + description for each. The set is read live from install.sh so it never drifts. `recommended: true` categories install by default; the rest are opt-in via --features.",
            inputSchema: { type: "object", properties: {}, additionalProperties: false }
        },
        {
            name: "list_rules",
            description: "List every steering rule in .claude/rules/ with its description and globs. Useful for the agent to understand what each rule covers before recommending which categories to install.",
            inputSchema: { type: "object", properties: {}, additionalProperties: false }
        },
        {
            name: "list_skills",
            description: "List every skill in .claude/skills/ with its description and reference file names. Skills are on-demand review agents; rules are always-loaded steering files.",
            inputSchema: { type: "object", properties: {}, additionalProperties: false }
        },
        {
            name: "preview_install",
            description: "Preview what `install.sh` would install for a given platform/language/features combination. Returns the install.sh --list output verbatim (catalog with [✓]/[ ] marks per file). No files written. Use this before calling `install` so the user can confirm the selection.",
            inputSchema: {
                type: "object",
                properties: {
                    platform: { type: "string", enum: ["apple", "android", "both"], description: "Default: both" },
                    apple_language: { type: "string", enum: ["swift", "objc", "both"], description: "Default: swift. Only relevant when platform includes apple." },
                    apple_platforms: { type: "string", description: "Comma-separated Apple sub-platforms (ios, macos, tvos, watchos, visionos) or 'all'. Default: ios,macos,tvos,watchos (no visionOS). Naming 'visionos' adds the visionOS rule. Only relevant when platform includes apple." },
                    android_platforms: { type: "string", description: "Comma-separated Android form factors (phone, tablet, wear, tv, auto) or 'all'. Default: phone,tablet. 'tablet' gates the large-screen / foldable rule (android-large-screen-best-practices.md) and the android-adaptive-layout-pro skill; other tokens are recorded in the manifest for future form-factor rules. Only relevant when platform includes android." },
                    features: { type: "string", description: "Comma-separated category list, or one of: 'recommended' (default), 'all'." },
                },
                additionalProperties: false
            }
        },
        {
            name: "install",
            description: "Run AppBootstrapAI's installer against a target directory. Copies skills, rules, settings.json, CLAUDE.md template, and .gitignore entries matching the selection. With --agents, also writes per-agent files (.github/copilot-instructions.md, .cursor/rules/*.mdc, GEMINI.md, AGENTS.md, .kiro/steering/*.md). Never overwrites existing CLAUDE.md/settings.json/agent files (prints what was skipped). Returns install.sh's stdout/stderr + exit code.",
            inputSchema: {
                type: "object",
                properties: {
                    target_dir: { type: "string", description: "Absolute path to the directory where AppBootstrapAI should be installed. Required." },
                    platform: { type: "string", enum: ["apple", "android", "both"], description: "Default: both" },
                    apple_language: { type: "string", enum: ["swift", "objc", "both"], description: "Default: swift. Only relevant when platform includes apple." },
                    apple_platforms: { type: "string", description: "Comma-separated Apple sub-platforms (ios, macos, tvos, watchos, visionos) or 'all'. Default: ios,macos,tvos,watchos (no visionOS). Naming 'visionos' adds the visionOS rule. Only relevant when platform includes apple." },
                    android_platforms: { type: "string", description: "Comma-separated Android form factors (phone, tablet, wear, tv, auto) or 'all'. Default: phone,tablet. 'tablet' gates the large-screen / foldable rule (android-large-screen-best-practices.md) and the android-adaptive-layout-pro skill; other tokens are recorded in the manifest for future form-factor rules. Only relevant when platform includes android." },
                    features: { type: "string", description: "Comma-separated category list, or one of: 'recommended' (default), 'all'." },
                    agents: { type: "string", description: "Comma-separated AI agents to install for: claude (default), copilot, cursor, gemini, codex, kiro, or 'all'. Additive." },
                    with_mcps: { type: "string", description: "Comma-separated MCP recipe names to add to .claude/settings.local.json (e.g. 'xcodebuildmcp,sentry'). See list-mcps in the bundle for available recipes." },
                },
                required: ["target_dir"],
                additionalProperties: false
            }
        },
        {
            name: "preview_upgrade",
            description: "Run `install.sh <target_dir> --upgrade` — a plan-only diff of what would change if the target re-installed from the current bundle. Writes NOTHING. Classifies each tracked file as up-to-date / safe-update / locally-edited / conflict / orphan / addition / rename, and surfaces a GitHub compare URL when the bundle commit differs. Use before deciding whether to re-run `install`.",
            inputSchema: {
                type: "object",
                properties: {
                    target_dir: { type: "string", description: "Absolute path to an existing AppBootstrapAI install (must contain .claude/.appbootstrap-manifest.json). Required." },
                    features: { type: "string", description: "Optional. Opt into new categories at upgrade time (e.g. 'recommended,spatial'). Defaults to whatever the manifest recorded." },
                },
                required: ["target_dir"],
                additionalProperties: false
            }
        },
        {
            name: "audit_project",
            description: "Audit a repo against the AppBootstrapAI bundle. Read-only. Returns { mode (new|existing), install {state, up_to_date, command[], preview_command[]}, summary, findings[], skills_to_run[], steering }. Each finding has severity, file:line locations, a one-line fix, and the rule_path / skill_path to read for a deep review. Findings accepted in the repo's audit baseline (.claude/appbootstrap-audit-baseline.json) are listed under baseline.suppressed instead; pass no_baseline to see everything. Pass skip_install_check when auditing a repo the user doesn't want the bundle installed into. kind is package (a library) or app. steering inventories the repo's AI steering files (CLAUDE.md, AGENTS.md, Cursor / Copilot / Kiro rules, skills) with the agent, load kind, size, and owner of each; steering-* findings flag stale paths and commands, placeholders, secrets, oversized or duplicated files, and lines that contradict a bundle rule. Pass steering_only to audit just those files. Findings are regex/file-presence hotspots: confirm or dismiss each by reading the code and the rule. Follow the audit prompt (audit only) or sync_and_audit prompt (install + audit) for the full workflow.",
            inputSchema: {
                type: "object",
                properties: {
                    target_dir: { type: "string", description: "Absolute path to the repo to audit. Required." },
                    no_baseline: { type: "boolean", description: "Ignore the audit baseline and report every finding." },
                    skip_install_check: { type: "boolean", description: "Audit without the bundle installed: drop the not-installed / outdated findings." },
                    steering_only: { type: "boolean", description: "Audit only the repo's AI steering files; skip the code checks and deep reviews." },
                },
                required: ["target_dir"],
                additionalProperties: false
            }
        },
        {
            name: "preview_uninstall",
            description: "Plan-only `install.sh <target_dir> --uninstall --dry-run`. Lists what an uninstall WOULD delete vs. keep (unchanged tracked files deleted; locally-edited files and CLAUDE.md/settings.json kept) without writing anything. Use before `uninstall`.",
            inputSchema: {
                type: "object",
                properties: {
                    target_dir: { type: "string", description: "Absolute path to an existing AppBootstrapAI install. Required." },
                },
                required: ["target_dir"],
                additionalProperties: false
            }
        },
        {
            name: "uninstall",
            description: "Reverse an AppBootstrapAI install in target_dir. Deletes every tracked file unchanged since install; keeps locally-edited files unless force_conflicts, keeps CLAUDE.md/settings.json unless purge, removes MCP entries unless keep_mcps; strips the .gitignore block + manifest. DESTRUCTIVE — call preview_uninstall first and confirm with the user.",
            inputSchema: {
                type: "object",
                properties: {
                    target_dir: { type: "string", description: "Absolute path to an existing AppBootstrapAI install. Required." },
                    purge: { type: "boolean", description: "Also delete CLAUDE.md and .claude/settings.json. Default false." },
                    keep_mcps: { type: "boolean", description: "Leave settings.local.json MCP entries untouched. Default false." },
                    force_conflicts: { type: "boolean", description: "Also delete locally-edited tracked files. Default false." },
                },
                required: ["target_dir"],
                additionalProperties: false
            }
        },
    ]
}));

server.setRequestHandler(CallToolRequestSchema, async (request: CallToolRequest) => {
    const { name, arguments: args } = request.params;
    try {
        switch (name) {
            case "recommend_setup":   return await toolRecommend(args as any);
            case "list_categories":   return await toolListCategories();
            case "list_rules":        return await toolListRules();
            case "list_skills":       return await toolListSkills();
            case "preview_install":   return await toolPreviewInstall(args as any);
            case "install":           return await toolInstall(args as any);
            case "preview_upgrade":   return await toolPreviewUpgrade(args as any);
            case "preview_uninstall": return await toolUninstall({ ...(args as any), dry_run: true });
            case "uninstall":         return await toolUninstall(args as any);
            case "audit_project":     return await toolAudit(args as any);
            default:
                throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${name}`);
        }
    } catch (e) {
        if (e instanceof McpError) throw e;
        throw new McpError(
            ErrorCode.InternalError,
            `${name} failed: ${e instanceof Error ? e.message : String(e)}`
        );
    }
});

// --- Prompts -------------------------------------------------------------------
//
// Prompts are sourced from the playbook files so the MCP path and the plain
// "read this Markdown" path never diverge.

server.setRequestHandler(ListPromptsRequestSchema, async () => ({
    prompts: [{
        name: "sync_and_audit",
        description: "Bring a repo up to the latest AppBootstrapAI bundle, then audit it against the bundle's rules and skills and write a report. Previews before writing; never commits.",
        arguments: [
            { name: "target_dir", description: "Absolute path to the repo. Defaults to the current working directory.", required: false },
        ],
    }, {
        name: "audit",
        description: "Audit a package, app, or repo against the AppBootstrapAI rules and skills without installing anything. Read-only; reports findings in chat.",
        arguments: [
            { name: "target_dir", description: "Absolute path to the repo. Defaults to the current working directory.", required: false },
        ],
    }],
}));

server.setRequestHandler(GetPromptRequestSchema, async (request) => {
    const name = request.params.name;
    if (name !== "sync_and_audit" && name !== "audit") {
        throw new McpError(ErrorCode.InvalidParams, `Unknown prompt: ${name}`);
    }
    const target = request.params.arguments?.target_dir || "the current working directory";
    // sync-and-audit.md defers its triage and report steps to audit.md, so both prompts carry it.
    const audit = await readFile(AUDIT_PLAYBOOK, "utf-8");
    const text = name === "audit"
        ? [
            `Run this playbook against ${target}. BUNDLE is ${REPO_ROOT}; skip step 1.`,
            "Use the audit_project tool with skip_install_check: true for step 2.",
            "",
            audit,
        ].join("\n")
        : [
            `Run this playbook against ${target}. BUNDLE is ${REPO_ROOT}.`,
            "Use the appbootstrap MCP tools where they map to a step: recommend_setup for `recommend`, preview_upgrade / preview_install for the preview, install for adopt, audit_project for `audit`. Use the shell for `upgrade --apply`.",
            "",
            await readFile(PLAYBOOK, "utf-8"),
            "",
            "---",
            "",
            "audit.md, which steps 2 and 3 above refer to:",
            "",
            audit,
        ].join("\n");
    return {
        description: name === "audit" ? "AppBootstrapAI audit" : "AppBootstrapAI sync and audit",
        messages: [{ role: "user", content: { type: "text", text } }],
    };
});

// Load the canonical category set from install.sh before accepting requests.
// If install.sh is missing/old, fail loudly at startup — better than serving
// a stale or empty category list. (The install/preview tools wouldn't work
// without install.sh anyway.)
try {
    CATEGORIES = await loadCategories();
} catch (e) {
    console.error(`appbootstrap-mcp: failed to load categories from install.sh: ${e instanceof Error ? e.message : String(e)}`);
    process.exit(1);
}

const transport = new StdioServerTransport();
await server.connect(transport);

// stderr is the canonical place for MCP servers to log to (stdout is the MCP transport).
console.error(`appbootstrap-mcp server connected via stdio (${CATEGORIES.length} categories loaded)`);
