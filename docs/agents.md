# Using with non-Claude AI agents

`install.sh` has a `--agents` flag for picking which agent(s) you want — additive, default `claude`. The bundle generates the right file shape for each agent from the same source `.claude/rules/`.

```bash
# Default — Claude Code only (today's behavior)
/path/to/AppBootstrapAI/install.sh .

# GitHub Copilot — writes .github/instructions/<name>.instructions.md per rule (applyTo-scoped)
/path/to/AppBootstrapAI/install.sh . --agents copilot

# Cursor — writes per-rule .cursor/rules/<name>.mdc files
/path/to/AppBootstrapAI/install.sh . --agents cursor

# Kiro — writes per-rule .kiro/steering/<name>.md files
/path/to/AppBootstrapAI/install.sh . --agents kiro

# Mixed team — install for Claude + Copilot + Cursor in one go
/path/to/AppBootstrapAI/install.sh . --agents claude,copilot,cursor

# Everything — claude + copilot + cursor + gemini + codex + kiro
/path/to/AppBootstrapAI/install.sh . --agents all
```

Per-agent file shape:

| Agent  | Token     | File(s) written                       | Format                       |
|--------|-----------|---------------------------------------|------------------------------|
| Claude Code  | `claude`  | `.claude/rules/`, `.claude/skills/`, `.claude/settings.json`, `CLAUDE.md` | Native — per-rule files + skill directories |
| GitHub Copilot | `copilot` | `.github/instructions/<name>.instructions.md`, `.github/copilot-instructions.md` | Per-rule [path-specific instructions](https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions); each rule's `globs` becomes `applyTo` (brace lists expanded), and `copilot-instructions.md` is a short pointer |
| Cursor | `cursor`  | `.cursor/rules/<name>.mdc`             | Per-rule files (1:1 with `.claude/rules/*.md`, just renamed) |
| Gemini CLI | `gemini`  | `GEMINI.md`, `.claude/rules/`        | A short index (about 13 KB for an Apple install): each rule's paths and its 2 to 5 always-on musts (`must:` in the rule's frontmatter), plus which `.claude/rules/` file to read in full before editing a matching file |
| Codex CLI / `AGENTS.md`-aware tools | `codex`   | `AGENTS.md`, `.claude/rules/`         | Same index as Gemini |
| Kiro | `kiro`    | `.kiro/steering/<name>.md`           | Per-rule [steering files](https://kiro.dev/docs/steering/); each rule's `globs` becomes `inclusion: fileMatch` + `fileMatchPattern`, so a rule loads only when a matching file is open |

**How it works:**

- **Same source, multiple targets.** Every agent gets content derived from the same `.claude/rules/*.md` source-of-truth (gated by `--platform` / `--apple-language` / `--features`). Output is deterministic — the Gemini/Codex indexes and the per-rule files (Copilot with `applyTo`, Cursor `.mdc`, Kiro steering with its rewritten `inclusion`/`fileMatchPattern` frontmatter) all produce the same bytes given the same inputs — so `--upgrade` can diff cleanly.
- **Only matching rules load.** An always-loaded file is paid for on every request, so no agent gets the full rule set up front. Gemini and Codex have no path scoping, so their index always carries each rule's musts and relies on the agent reading the full rule for the rest; it's about 13 KB instead of the 180 KB the full rule text used to be.
- **Skills are Claude-only.** Skills are procedural sub-agents that only run inside Claude Code. Non-Claude agents get rules only. If you want a skill's checklist in another agent's context, copy it into the relevant rule manually.
- **Existing files are never overwritten on install.** If you already have `.github/copilot-instructions.md` or `GEMINI.md`, install skips and prints a notice. `--upgrade` does the 3-way diff like any other tracked file.
- **`--upgrade --apply` opts in / out of agents.** Pass `--agents` on the command line to opt into a new agent (its files show up as additions). Pass `--agents <fewer>` + `--prune` to drop an agent (its files appear as orphans and get deleted).
- **The manifest tracks per-agent.** `selection.agents_input` / `selection.agents_resolved` and per-file `type: agent-file-<name>` entries so the upgrade flow knows which files came from which agent.

### Alternative: external sync tools

If you'd rather keep a single source-of-truth and let another tool fan out to a wider set of agents (Cline, Goose, Roo, Windsurf, Amp, Antigravity, Factory Droid, etc.), point one of these at `.claude/`:

| Tool | Approach |
|------|----------|
| **[`ruler`](https://github.com/intellectronica/ruler)** | Reads from a unified source (you can point it at `.claude/rules/`) and applies the same rules to every supported agent's expected path on `ruler apply`. Maintains the per-tool path matrix for you. |
| **[`block/ai-rules`](https://github.com/block/ai-rules)** | Manages rules, commands, and skills across Claude, Cline, Codex, Copilot, Cursor, Firebender, Gemini, Goose, Kilocode, Roo. Installs via `curl` to `~/.local/bin/ai-rules`. |
| **[`lbb00/ai-rules-sync`](https://github.com/lbb00/ai-rules-sync)** | npm-installable CLI; similar fan-out model. |

Use a sync tool when you need agents that `install.sh --agents` doesn't cover, or when you want a single watch-and-rebuild loop instead of explicit `--upgrade --apply` runs.
