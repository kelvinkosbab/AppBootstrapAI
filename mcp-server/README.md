# AppBootstrapAI MCP Server

A [Model Context Protocol](https://modelcontextprotocol.io) server that exposes AppBootstrapAI's `install.sh` as structured tools for AI agents.

If you're using Claude Code (or another MCP-aware agent), this lets the agent **introspect** the catalog and **install** the bundle through typed tool calls rather than parsing shell output. The agent gets argument validation, structured JSON responses, and clear error messages.

If you'd rather just run `install.sh` by hand or via shell tool — that still works too. The MCP server is purely additive.

## Tools exposed

| Tool | Description |
|------|-------------|
| `recommend_setup` | **Call this first.** Analyzes `target_dir` (read-only) and returns the recommended action as JSON — `state`, `platform`, `apple_language`, `features`, `action`, `feature_reasons`, and a ready-to-run `command[]` / `preview_command[]`. Detects managed-state + framework usage (FoundationModels→`ai`, Core Data/SwiftData→`persistence`, Room→`persistence`, R8→`shrinking`, fastlane/CI→`deployment`, …). |
| `list_categories` | Returns the feature categories (name + `recommended` flag + description), read live from `install.sh`. Useful before recommending `--features`. |
| `list_rules` | Returns every steering rule in `.claude/rules/` with its description and `globs:` from frontmatter. |
| `list_skills` | Returns every skill in `.claude/skills/` with its description and reference-file names. |
| `preview_install` | Runs `install.sh --list` with the given `platform`, `apple_language`, `features` and returns the catalog with `[✓]/[ ]` marks. No files written — preview only. |
| `install` | Runs `install.sh` against `target_dir`. Returns exit code + stdout + stderr. Same overwrite-policy as the CLI (never replaces existing `CLAUDE.md` / `settings.json`). |
| `preview_upgrade` | Plan-only 3-way diff of `target_dir` vs. the current bundle. Writes nothing. |
| `preview_uninstall` | Plan-only `--uninstall --dry-run`: what an uninstall would delete vs. keep. Writes nothing. |
| `uninstall` | Reverses an install (`purge` / `keep_mcps` / `force_conflicts` options). Destructive — call `preview_uninstall` first. |

Each tool's input schema is fully typed (see `src/index.ts`), so agents get autocomplete-grade hints when calling. The intended loop is **`recommend_setup` → preview → act**.

## Setup

### Prerequisites

- Node.js 20 or newer (the MCP TypeScript SDK requires modern Node)
- A clone of the AppBootstrapAI repo

### Build

```bash
cd mcp-server
npm install        # `prepare` script runs `npm run build` automatically
```

That produces `dist/index.js`, the executable MCP server entry point.

### Wire into Claude Code

Add to your project's `.claude/settings.json` (or your global `~/.claude/settings.json`):

```json
{
  "mcpServers": {
    "appbootstrap": {
      "command": "node",
      "args": ["/absolute/path/to/AppBootstrapAI/mcp-server/dist/index.js"]
    }
  }
}
```

Restart Claude Code; the nine tools become callable from any Claude session.

### Wire into other MCP clients

The transport is stdio. Any MCP-compatible client (Cursor, Gemini CLI's experimental MCP support, Kiro, Codex CLI, etc.) accepts a stdio-launched subprocess. The config shape varies; see your client's MCP-server docs. The `command` is always `node` and the `args` is the absolute path to `dist/index.js`.

## Usage from an agent

Once configured, an agent can call tools like:

```
recommend_setup({ target_dir: "/Users/me/Projects/MyApp" })
→ Analyzes the repo. Returns { state, platform, features, action, command[] }. Call this first.

list_categories()
→ Returns the feature categories with recommended flags. Agent learns what's installable.

preview_install({ platform: "apple", apple_language: "swift", features: "recommended" })
→ Returns the install.sh --list output as plain text. Agent shows the user what would land.

install({ target_dir: "/Users/me/Projects/NewApp", platform: "apple", features: "recommended,ai" })
→ Runs install.sh against the target directory. Agent reports the exit code + stdout.
```

A typical Claude conversation:

> **User:** Bootstrap AppBootstrapAI in this repo, just for Apple, with the AI/Foundation Models category included.
>
> **Claude:** I'll preview what will install first. [calls `preview_install({ platform: "apple", features: "recommended,ai" })`] — shows you the catalog — then run the install. [calls `install({ target_dir: "<cwd>", ... })`]

The agent picks the right arguments because the MCP tool descriptions enumerate the valid values; less guessing than parsing `--help` output.

## Comparison to running install.sh directly

| | Direct shell | MCP server |
|---|--------------|------------|
| Speed | Same (both shell out to install.sh) | Same |
| Argument validation | Bash error after launch | Validated in the MCP layer, clearer messages |
| Structured output | Free-form text (agent parses) | JSON for catalog tools; raw text for install/preview |
| Schema for agent | None (agent reads `--help`) | Typed `inputSchema` per tool |
| Dependencies | bash only | bash + node 20+ |

The shell path is fine for most cases. The MCP server is for teams that want the structured-tool experience or are wiring AppBootstrapAI into multi-tool workflows.

## Development

```bash
# After editing src/
npm run build       # rebuild dist/
npm start           # launch the server (mostly useful for debugging)
```

The server logs to stderr (`appbootstrap-mcp server connected via stdio`); stdout is reserved for the MCP transport protocol.

## Roadmap

- Publish to npm as `@kelvinkosbab/appbootstrap-mcp` so `npx -y @kelvinkosbab/appbootstrap-mcp` works without cloning the repo.
- Consider a `describe_skill(name)` tool that returns the full SKILL.md body + reference contents for skills the agent wants to deep-read.
- Consider a `read_rule(name)` tool for the same on the rules side.
- Track `install.sh`'s feature-category list automatically rather than maintaining the parallel TypeScript list in `src/index.ts`.

## License

MIT. Same as the parent repo.
