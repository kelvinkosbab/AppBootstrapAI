// One round trip per tool and prompt, through a real MCP client connected to
// the server in memory. install / upgrade / audit / uninstall run the bundle's
// install.sh against a temp directory. Run with `npm test` (builds first).

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createServer } from "../dist/server.js";

let client;
let target;
const manifest = () => join(target, ".claude", ".appbootstrap-manifest.json");

before(async () => {
    const { server } = await createServer();
    const [clientSide, serverSide] = InMemoryTransport.createLinkedPair();
    client = new Client({ name: "tools-test", version: "0.0.0" });
    await Promise.all([server.connect(serverSide), client.connect(clientSide)]);
    // A minimal Swift package, so platform detection has something to find.
    target = mkdtempSync(join(tmpdir(), "appbootstrap-mcp-"));
    writeFileSync(join(target, "Package.swift"), "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"Demo\")\n");
});

after(async () => {
    await client?.close();
    if (target) rmSync(target, { recursive: true, force: true });
});

async function call(name, args = {}) {
    const result = await client.callTool({ name, arguments: args });
    return { result, text: result.content.map(c => c.text).join("") };
}

async function callOk(name, args) {
    const r = await call(name, args);
    assert.ok(!r.result.isError, `${name} failed: ${r.text}`);
    return r.text;
}

test("lists every tool and prompt", async () => {
    const { tools } = await client.listTools();
    assert.deepEqual(tools.map(t => t.name).sort(), [
        "audit_project", "install", "list_categories", "list_rules", "list_skills",
        "preview_install", "preview_uninstall", "preview_upgrade", "recommend_setup", "uninstall",
    ]);
    const install = tools.find(t => t.name === "install");
    assert.deepEqual(install.inputSchema.required, ["target_dir"]);
    const { prompts } = await client.listPrompts();
    assert.deepEqual(prompts.map(p => p.name).sort(), ["audit", "sync_and_audit"]);
});

test("list_categories reads the set from install.sh", async () => {
    const { categories } = JSON.parse(await callOk("list_categories"));
    const core = categories.find(c => c.name === "core");
    assert.ok(core?.recommended);
    assert.ok(core.description.length > 0);
});

test("list_rules returns frontmatter", async () => {
    const { rules } = JSON.parse(await callOk("list_rules"));
    const rule = rules.find(r => r.filename === "apple-spm-package-conventions.md");
    assert.ok(rule?.description);
});

test("list_skills returns references", async () => {
    const { skills } = JSON.parse(await callOk("list_skills"));
    const skill = skills.find(s => s.name === "swift-package-pro");
    assert.ok(skill?.description);
    assert.ok(skill.references.length > 0);
});

test("preview_install lists the selection", async () => {
    const text = await callOk("preview_install", { platform: "apple", features: "core,packaging" });
    assert.match(text, /apple-spm-package-conventions\.md/);
});

test("rejects a relative target_dir", async () => {
    const { result, text } = await call("recommend_setup", { target_dir: "audit" });
    assert.ok(result.isError);
    assert.match(text, /absolute path/);
});

test("rejects an unknown feature category", async () => {
    const { result, text } = await call("preview_install", { features: "core,nope" });
    assert.ok(result.isError);
    assert.match(text, /Unknown feature category: "nope"/);
});

test("rejects a bad enum value", async () => {
    const { result } = await call("preview_install", { platform: "windows" });
    assert.ok(result.isError);
});

test("recommend_setup suggests adopting an unmanaged repo", async () => {
    const rec = JSON.parse(await callOk("recommend_setup", { target_dir: target }));
    assert.equal(rec.platform, "apple");
    assert.ok(Array.isArray(rec.command));
});

test("install, then upgrade, audit, and uninstall", async () => {
    const installed = JSON.parse(await callOk("install", { target_dir: target, features: "core,packaging" }));
    assert.equal(installed.exit_code, 0);
    assert.match(installed.stdout, /apple/);
    assert.ok(existsSync(manifest()));

    const plan = await callOk("preview_upgrade", { target_dir: target });
    assert.ok(plan.length > 0);
    assert.ok(existsSync(manifest()));

    const audit = JSON.parse(await callOk("audit_project", { target_dir: target }));
    assert.ok(Array.isArray(audit.findings));

    const preview = JSON.parse(await callOk("preview_uninstall", { target_dir: target }));
    assert.equal(preview.dry_run, true);
    assert.ok(existsSync(manifest()), "preview_uninstall must not delete anything");

    const removed = JSON.parse(await callOk("uninstall", { target_dir: target }));
    assert.equal(removed.dry_run, false);
    assert.ok(!existsSync(manifest()));
});

test("prompts carry the playbooks", async () => {
    const audit = await client.getPrompt({ name: "audit", arguments: { target_dir: "/tmp/x" } });
    assert.match(audit.messages[0].content.text, /against \/tmp\/x/);
    const sync = await client.getPrompt({ name: "sync_and_audit", arguments: {} });
    assert.match(sync.messages[0].content.text, /the current working directory/);
});
