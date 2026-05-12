#!/usr/bin/env node
/**
 * AppBootstrapAI MCP server.
 *
 * Exposes the bundle's install.sh as structured tools that AI agents
 * (Claude Code, Cursor, Gemini CLI, Kiro, Codex) can invoke through MCP
 * rather than parsing shell output.
 *
 * Tools:
 *   - list_categories     Return the 13 feature categories with descriptions.
 *   - list_rules          Return every rule's frontmatter (description, globs, file path).
 *   - list_skills         Return every skill's frontmatter + its reference files.
 *   - preview_install     Run `install.sh --list` for a given selection; return parsed catalog.
 *   - install             Run `install.sh` against a target directory.
 *
 * Communicates over stdio (the standard MCP transport for local subprocess servers).
 * Configure a client by pointing at the compiled `dist/index.js`.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
    CallToolRequestSchema,
    ListToolsRequestSchema,
    McpError,
    ErrorCode,
    type CallToolRequest,
} from "@modelcontextprotocol/sdk/types.js";
import { spawn } from "node:child_process";
import { readFile, readdir, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

// --- Locate the AppBootstrapAI repo root --------------------------------------
//
// The repo root is two levels up from this file's directory:
//   <repo>/mcp-server/dist/index.js  →  REPO_ROOT = <repo>
// During `npm run start` from source, the same relationship holds via tsx.

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const REPO_ROOT = resolve(__dirname, "..", "..");
const INSTALL_SH = join(REPO_ROOT, "install.sh");
const RULES_DIR = join(REPO_ROOT, ".claude", "rules");
const SKILLS_DIR = join(REPO_ROOT, ".claude", "skills");

// --- Static category metadata -------------------------------------------------
// Mirrors the case statement in install.sh's file_category() and the header
// comment in install.sh. Kept in sync manually — there isn't a single source
// of truth for categories yet.

const CATEGORIES = [
    { name: "core",            recommended: true,  description: "Project-level README/CHANGELOG/CONTRIBUTING/ADR patterns." },
    { name: "concurrency",     recommended: true,  description: "Swift 6.2 strict concurrency / Kotlin coroutines structured concurrency." },
    { name: "ui",              recommended: true,  description: "SwiftUI/MVVM / Jetpack Compose patterns + accessibility." },
    { name: "testing",         recommended: true,  description: "Test strategy + coverage gates (Apple + Android)." },
    { name: "docs",            recommended: true,  description: "DocC / KDoc documentation strategy." },
    { name: "error-handling",  recommended: true,  description: "Swift typed throws / Result / LocalizedError." },
    { name: "packaging",       recommended: true,  description: "Package.swift / Gradle conventions / SPM and Gradle authoring." },
    { name: "logging",         recommended: true,  description: "os.Logger discipline (privacy markers, subsystem/category)." },
    { name: "localization",    recommended: true,  description: "String Catalogs / strings.xml / plurals / RTL." },
    { name: "persistence",     recommended: false, description: "Core Data under Swift 6 strict concurrency." },
    { name: "ai",              recommended: false, description: "Apple Foundation Models (iOS 26+)." },
    { name: "migration",       recommended: false, description: "Android XML/Fragment → Compose migration." },
    { name: "shrinking",       recommended: false, description: "R8 / ProGuard configuration and keep-rule discipline." },
];

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

async function toolPreviewInstall(args: { platform?: string; apple_language?: string; features?: string }) {
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

    const result = await runCommand(
        "bash",
        [INSTALL_SH, "--list", "--platform", platform, "--apple-language", appleLanguage, "--features", features]
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
    features?: string;
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

    const result = await runCommand(
        "bash",
        [INSTALL_SH, args.target_dir, "--platform", platform, "--apple-language", appleLanguage, "--features", features]
    );

    const summary = {
        exit_code: result.code,
        target_dir: args.target_dir,
        platform,
        apple_language: appleLanguage,
        features,
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

// --- MCP wiring ---------------------------------------------------------------

const server = new Server(
    {
        name: "appbootstrap",
        version: "0.1.0",
    },
    {
        capabilities: { tools: {} },
    }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [
        {
            name: "list_categories",
            description: "List the 13 feature categories AppBootstrapAI's install.sh recognizes (core, concurrency, ui, testing, docs, error-handling, packaging, logging, localization, persistence, ai, migration, shrinking). Returns name + recommended flag + description for each.",
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
                    features: { type: "string", description: "Comma-separated category list, or one of: 'recommended' (default), 'all'." },
                },
                additionalProperties: false
            }
        },
        {
            name: "install",
            description: "Run AppBootstrapAI's installer against a target directory. Copies skills, rules, settings.json, CLAUDE.md template, and .gitignore entries matching the selection. Never overwrites existing CLAUDE.md or settings.json (prints what was skipped). Returns install.sh's stdout/stderr + exit code.",
            inputSchema: {
                type: "object",
                properties: {
                    target_dir: { type: "string", description: "Absolute path to the directory where AppBootstrapAI should be installed. Required." },
                    platform: { type: "string", enum: ["apple", "android", "both"], description: "Default: both" },
                    apple_language: { type: "string", enum: ["swift", "objc", "both"], description: "Default: swift. Only relevant when platform includes apple." },
                    features: { type: "string", description: "Comma-separated category list, or one of: 'recommended' (default), 'all'." },
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
            case "list_categories": return await toolListCategories();
            case "list_rules":      return await toolListRules();
            case "list_skills":     return await toolListSkills();
            case "preview_install": return await toolPreviewInstall(args as any);
            case "install":         return await toolInstall(args as any);
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

const transport = new StdioServerTransport();
await server.connect(transport);

// stderr is the canonical place for MCP servers to log to (stdout is the MCP transport).
console.error("appbootstrap-mcp server connected via stdio");
