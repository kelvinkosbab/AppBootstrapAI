// Copies the AppBootstrapAI bundle into ./bundle so the published package can
// run install.sh without a clone. Runs from `npm pack` / `npm publish`.
import { cpSync, existsSync, rmSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repo = resolve(pkg, "..");
const out = join(pkg, "bundle");
const entries = [
    "install.sh", "lib", ".claude", "templates", "playbooks", "mcp-recipes",
    "scripts", "RENAMES.md", "LICENSE",
];

rmSync(out, { recursive: true, force: true });
for (const entry of entries) {
    const src = join(repo, entry);
    if (!existsSync(src)) throw new Error(`missing bundle entry: ${src}`);
    cpSync(src, join(out, entry), {
        recursive: true,
        filter: (p) => !p.includes("__pycache__") && !p.endsWith("settings.local.json"),
    });
}
let commit = "unknown";
try {
    commit = execFileSync("git", ["-C", repo, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
} catch {}
writeFileSync(join(out, ".bundle-commit"), `${commit}\n`);
console.log(`Bundled AppBootstrapAI ${commit.slice(0, 12)} into ${out}`);
