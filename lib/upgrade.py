#!/usr/bin/env python3
"""Plan + apply executor for `install.sh --upgrade [--apply ...]`.

This is the brain of the upgrade flow. It reads the target's manifest,
walks every tracked file, applies a 3-way hash diff against the current
bundle, classifies each entry, prints a categorized plan, and (when
`--apply` is set) executes the plan: copies safe updates, renames files
where RENAMES.md says to, removes orphans under --prune, lays down
additions, and rebuilds the manifest from disk state.

It also handles the v1 → v2 manifest migration (--migrate-manifest) and
the MCP-side 3-way diff against .claude/settings.local.json.

Inputs are all positional sys.argv slots — install.sh assembles them. See
the unpacking block below for the order. The heavy lifting that has to
happen on the bash side (computing bundle hashes, materializing the
agent-overlay dir, parsing flags) is done by install.sh before we run.

Args:
    sys.argv[ 1] — manifest_path        — target's manifest.json
    sys.argv[ 2] — target_root          — absolute install root
    sys.argv[ 3] — bundle_all_path      — pipe-separated list of every shippable bundle file
    sys.argv[ 4] — in_scope_path        — newline-separated list of bundle files in scope under current selection
    sys.argv[ 5] — renames_path         — RENAMES.md path (may not exist)
    sys.argv[ 6] — platform             — current --platform (effective)
    sys.argv[ 7] — apple_lang           — current --apple-language
    sys.argv[ 8] — features             — current --features input string
    sys.argv[ 9] — script_dir           — absolute path to the bundle root
    sys.argv[10] — apply_flag           — "true" to execute the plan
    sys.argv[11] — force_conflicts_flag — "true" to overwrite conflicted files / renames
    sys.argv[12] — prune_flag           — "true" to delete orphans + out-of-scope
    sys.argv[13] — migrate_manifest_flag — "true" to rewrite v1 manifest as v2 baseline
    sys.argv[14] — dry_run_flag         — "true" to preview without writing
    sys.argv[15] — bundle_commit        — current bundle's git HEAD or "unknown"
    sys.argv[16] — settings_local_path  — target's .claude/settings.local.json
    sys.argv[17] — mcp_recipes_dir      — bundle's mcp-recipes/ directory
    sys.argv[18] — bundle_overlay_dir   — temp dir holding agent-derived files (Cursor .mdc, concat agents)
    sys.argv[19] — agents_input         — current --agents input string
    sys.argv[20] — agents_resolved_str  — space-separated resolved agent names
    sys.argv[21] — bundle_gh_remote     — "owner/repo" for the bundle's GitHub origin, or "" if not on GitHub

Output: human-readable plan + apply-time progress + manifest refresh notices.

Exit codes:
    0 — plan printed (no --apply) OR apply completed OR v1 manifest migrated
    2 — schema_version > 2 (newer manifest than this installer understands)
"""
import hashlib, json, os, shutil, sys, datetime

(manifest_path, target_root, bundle_all_path, in_scope_path, renames_path,
 platform, apple_lang, features, script_dir,
 apply_flag, force_conflicts_flag, prune_flag, migrate_manifest_flag, dry_run_flag,
 bundle_commit,
 settings_local_path, mcp_recipes_dir, bundle_overlay_dir,
 agents_input, agents_resolved_str, bundle_gh_remote) = sys.argv[1:22]
agents_resolved = agents_resolved_str.split() if agents_resolved_str else []

def bundle_source_for(rel_path):
    """Resolve the source for a given target-relative path.

    Agent-derived files (Cursor .mdc, Copilot/Gemini/Codex concat) live in the
    overlay dir — they're not directly on disk in the bundle. Everything else
    (rules, skills, settings.json, CLAUDE.md template) maps to script_dir.

    For CLAUDE.md specifically, the source is the platform-specific template
    under templates/, but we don't auto-apply CLAUDE.md anyway, so this never
    gets used for it.
    """
    overlay = os.path.join(bundle_overlay_dir, rel_path)
    if os.path.exists(overlay):
        return overlay
    return os.path.join(script_dir, rel_path)

APPLY            = (apply_flag           == "true")
FORCE_CONFLICTS  = (force_conflicts_flag == "true")
PRUNE            = (prune_flag           == "true")
MIGRATE_MANIFEST = (migrate_manifest_flag == "true")
DRY_RUN          = (dry_run_flag         == "true")

# ----- Read manifest --------------------------------------------------------
with open(manifest_path) as f:
    manifest = json.load(f)

schema = manifest.get("schema_version", 1)

if schema == 1:
    if not MIGRATE_MANIFEST:
        print("==> Manifest is schema v1 (no content hashes recorded at install).")
        print("    The plan-and-apply upgrade flow needs hashes to safely diff your tree.")
        print("")
        print("    Two ways forward:")
        print("    1. Re-run install.sh (without --upgrade) to write a fresh v2 manifest.")
        print("       Existing files are not overwritten — settings.json, CLAUDE.md, and")
        print("       any rules you edited are preserved (the installer never overwrites).")
        print("       This is the lowest-risk path.")
        print("")
        print("    2. Re-run as `--upgrade --apply --migrate-manifest` to rewrite the")
        print("       manifest from current disk contents as a v2 baseline. No file is")
        print("       touched; only the manifest changes. After that, future --upgrade")
        print("       runs can do real 3-way diffs.")
        print("")
        print("    Aborting plan — no v1 → v2 hash inference without --migrate-manifest.")
        sys.exit(0)
    # MIGRATE_MANIFEST + v1: rebuild manifest from disk and exit.
    def sha256_path(p):
        if not os.path.exists(p):
            return None
        h = hashlib.sha256()
        with open(p, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()

    new_files = []
    dropped = []
    for entry in manifest.get("files", []):
        rel = entry["path"]
        abs_p = os.path.join(target_root, rel)
        type_ = entry.get("type", "rule")
        # v1 sometimes had a single "skill" entry per directory; expand to one
        # per file by walking the on-disk skill dir.
        if type_ == "skill":
            skill_name = rel.rstrip("/").split("/")[-1]
            if os.path.isdir(abs_p):
                for root, _, fnames in os.walk(abs_p):
                    for fn in fnames:
                        ap = os.path.join(root, fn)
                        rp = os.path.relpath(ap, target_root).replace(os.sep, "/")
                        new_files.append({
                            "path": rp,
                            "type": "skill-file",
                            "category": entry.get("category", "-"),
                            "sha256": sha256_path(ap),
                            "skill": skill_name,
                        })
            else:
                dropped.append(rel)
            continue
        # Non-content entries (gitignore-block) → carry forward with null hash.
        if type_ == "gitignore-block":
            new_files.append({
                "path": rel,
                "type": "gitignore-block",
                "category": entry.get("category", "-"),
                "sha256": None,
            })
            continue
        if not os.path.exists(abs_p):
            dropped.append(rel)
            continue
        new_files.append({
            "path": rel,
            "type": type_,
            "category": entry.get("category", "-"),
            "sha256": sha256_path(abs_p),
        })

    sel = manifest.get("selection", {})
    new_manifest = {
        "schema_version": 2,
        "installed_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "bundle_commit": bundle_commit if bundle_commit else "unknown",
        "selection": {
            "platform": sel.get("platform", platform),
            "apple_language": sel.get("apple_language", apple_lang),
            "features_input": sel.get("features_input", features),
            "features_resolved": sel.get("features_resolved", []),
            # v1 didn't have agents — default to claude (the only agent v1 supported).
            "agents_input": "claude",
            "agents_resolved": ["claude"],
        },
        "files": new_files,
        "mcps_installed": [],   # v1 had string-array mcps_requested; not migrated automatically
    }
    if DRY_RUN:
        print(f"==> [dry-run] Would migrate v1 → v2 manifest at {manifest_path}.")
        print(f"               {len(new_files)} file entries; {len(dropped)} dropped (file missing on disk).")
        print("               (v1 mcps_requested not carried over — re-add MCPs via --with-mcps.)")
    else:
        with open(manifest_path, "w") as f:
            json.dump(new_manifest, f, indent=2)
            f.write("\n")
        print(f"==> Migrated manifest from v1 → v2: {manifest_path}")
        print(f"    Recorded {len(new_files)} file entries with sha256 baselines from current disk.")
        if dropped:
            print(f"    Dropped {len(dropped)} entries whose files are missing on disk:")
            for d in dropped[:10]:
                print(f"      {d}")
            if len(dropped) > 10:
                print(f"      … and {len(dropped) - 10} more")
        print("    Note: v1 mcps_requested was not migrated — re-add MCPs via --with-mcps if needed.")
        print("    Future --upgrade runs can now do real 3-way diffs.")
    sys.exit(0)

if schema > 2:
    print(f"error: manifest schema_version={schema} is newer than this installer understands.", file=sys.stderr)
    print("       Update install.sh from the bundle and retry.", file=sys.stderr)
    sys.exit(2)

# ----- Load bundle data ------------------------------------------------------
def load_pipe_file(path, n_fields):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("|", n_fields - 1)
            # pad to n_fields
            while len(parts) < n_fields:
                parts.append("")
            rows.append(parts)
    return rows

bundle_all_rows = load_pipe_file(bundle_all_path, 5)
# Map: rel_path → (type, category, sha256, skill_name_or_template_src)
bundle_all = {r[0]: (r[1], r[2], r[3], r[4]) for r in bundle_all_rows}

in_scope = set()
with open(in_scope_path) as f:
    for line in f:
        line = line.strip()
        if line:
            in_scope.add(line)

# ----- Parse RENAMES.md ------------------------------------------------------
# Two forms supported:
#   - `apple-old.md → apple-new.md`     — rule file rename. Resolves to
#                                          .claude/rules/apple-old.md →
#                                          .claude/rules/apple-new.md
#   - `swift-old-pro → swift-new-pro`   — skill directory rename. Applied as
#                                          a path-prefix substitution at
#                                          classification time, so every file
#                                          under .claude/skills/swift-old-pro/
#                                          folds to .claude/skills/swift-new-pro/<rest>.
renames = {}          # exact old_path → new_path for rule files
skill_renames = {}    # old_skill_name → new_skill_name (prefix-based)
if os.path.exists(renames_path):
    with open(renames_path) as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            # Strip backticks if the line is fenced
            if line.startswith("```") or line == "```":
                continue
            # Accept either Unicode arrow or ASCII ->
            sep = None
            if "→" in line:
                sep = "→"
            elif "->" in line:
                sep = "->"
            else:
                continue
            old, new = [s.strip() for s in line.split(sep, 1)]
            if old.endswith(".md") and new.endswith(".md"):
                # Rule rename (file-level, exact match).
                renames[f".claude/rules/{old}"] = f".claude/rules/{new}"
            elif "/" not in old and "/" not in new and "." not in old and "." not in new:
                # Skill directory rename (bare names, no slashes / dots).
                skill_renames[old] = new

def resolve_rename(rel_path):
    """Apply rule-file + skill-dir renames; follow the chain to convergence."""
    cur = rel_path
    seen = set()
    while True:
        if cur in seen:
            break  # cycle guard
        seen.add(cur)
        # Exact-match rename takes priority.
        if cur in renames:
            cur = renames[cur]
            continue
        # Skill-dir prefix rewrite.
        rewritten = None
        for old_skill, new_skill in skill_renames.items():
            prefix = f".claude/skills/{old_skill}/"
            if cur.startswith(prefix):
                rewritten = f".claude/skills/{new_skill}/" + cur[len(prefix):]
                break
        if rewritten:
            cur = rewritten
            continue
        break
    return cur

# ----- Read every file's current disk hash from manifest -------------------
def sha256_path(p):
    if not os.path.exists(p):
        return None
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

# ----- Classify each manifest entry ----------------------------------------
up_to_date = []
safe_updates = []
local_edits = []
conflicts = []
orphans = []
out_of_scope = []
renames_safe = []      # safe-to-execute renames: no local edit on old path
renames_conflict = []  # rename + (local edit OR bundle drift) → needs --force-conflicts

manifest_paths = set()
for entry in manifest.get("files", []):
    rel = entry["path"]
    manifest_paths.add(rel)
    installed_hash = entry.get("sha256")
    abs_path = os.path.join(target_root, rel)
    current_hash = sha256_path(abs_path) if installed_hash is not None else None

    # Rename: apply rule-file + skill-dir renames (chain followed to convergence).
    rename_target = resolve_rename(rel)
    is_renamed = rename_target != rel

    bundle_lookup_path = rename_target
    bundle_info = bundle_all.get(bundle_lookup_path)

    # Non-content entries (gitignore-block) — skip diff, leave for Phase 3.
    if installed_hash is None and entry.get("type") == "gitignore-block":
        continue

    if bundle_info is None:
        # File doesn't exist in bundle anymore → orphan.
        orphans.append({
            "path": rel,
            "type": entry.get("type"),
            "current_present": current_hash is not None,
        })
        continue

    bundle_hash = bundle_info[2]
    # Never auto-update CLAUDE.md (template) or settings.json — they're the
    # user's files even though we seeded them at install. Surface upstream
    # changes as informational notes; the user diffs manually.
    if entry.get("type") in ("template", "settings"):
        if installed_hash == bundle_hash:
            up_to_date.append({"path": rel, "type": entry.get("type")})
        else:
            note_target = bundle_info[3] if entry.get("type") == "template" else rel
            local_edits.append({
                "path": rel,
                "type": entry.get("type"),
                "note": f"yours — but {note_target} has advanced upstream. Diff manually if you want the new content.",
            })
        continue

    # Standard 4-case for content files.
    row = {
        "path": rel,
        "type": entry.get("type"),
        "category": entry.get("category"),
        "skill": entry.get("skill"),
        "renamed_to": rename_target if is_renamed else None,
    }

    # Renames are handled separately — apply writes the new path and deletes
    # the old one regardless of whether the file at the old path matches bundle.
    # Safety still matters: if the user has edited the file at the old path,
    # executing the rename would lose that edit.
    if is_renamed:
        # Detect collision: new path already exists on disk AND isn't itself in
        # the manifest. That's a user-authored file at the rename target —
        # never overwrite. Surface as a conflict so the user resolves manually.
        new_abs = os.path.join(target_root, rename_target)
        new_path_collision = (
            os.path.exists(new_abs)
            and rename_target not in {e["path"] for e in manifest.get("files", [])}
        )
        if new_path_collision:
            renames_conflict.append({**row, "note": f"target path already exists at {rename_target}"})
        elif current_hash == bundle_hash or current_hash == installed_hash:
            # No local edit at old path (current matches either installed-baseline
            # or the new bundle content) → safe to rename.
            renames_safe.append(row)
        else:
            # current_hash differs from BOTH installed AND bundle → user has
            # local edits that don't match bundle. Renaming loses them.
            renames_conflict.append(row)
        continue

    # Out-of-scope: bundle still has it but current selection wouldn't install it.
    if bundle_lookup_path not in in_scope:
        out_of_scope.append(row)
        continue

    # Classification — anchor on "is disk already at bundle?" first. This
    # correctly handles the case where the user upgraded once already (so disk
    # matches bundle even though installed_hash is stale).
    if current_hash == bundle_hash:
        # Disk is at latest — no work needed, manifest may be stale (refresh on apply).
        up_to_date.append(row)
    elif current_hash == installed_hash:
        # No local edits since install. Bundle has new content → safe update.
        safe_updates.append(row)
    elif installed_hash == bundle_hash:
        # Bundle unchanged from install, but disk differs → local edit only.
        local_edits.append(row)
    else:
        # current, installed, and bundle all differ → true conflict.
        conflicts.append(row)

# ----- Additions: bundle in-scope, not in manifest --------------------------
# (Skip rename targets — they're already accounted for as renames of an existing path.)
# For rule renames, that's just `renames.values()`. For skill renames, we
# need to apply the prefix to every manifest entry under the OLD skill dir
# so the corresponding NEW-dir file is marked as a rename target (not an addition).
rename_targets = set(renames.values())
for entry in manifest.get("files", []):
    resolved = resolve_rename(entry["path"])
    if resolved != entry["path"]:
        rename_targets.add(resolved)
additions = []
for rel in sorted(in_scope):
    if rel in manifest_paths:
        continue
    if rel in rename_targets:
        continue
    info = bundle_all.get(rel)
    if info is None:
        continue
    type_, cat, _, skill = info
    if type_ == "settings" and os.path.exists(os.path.join(target_root, rel)):
        # settings.json already exists on disk; install path would skip it.
        # We don't surface this as an addition in Phase 2.
        continue
    if type_ == "template" and os.path.exists(os.path.join(target_root, rel)):
        continue
    additions.append({"path": rel, "type": type_, "category": cat, "skill": skill})

# ----- MCP 3-way classification ---------------------------------------------
# For each MCP entry in mcps_installed, compute the same 3-way diff:
#   installed_hash  — from the manifest (config we wrote at install)
#   current_hash    — hash of the entry currently in settings.local.json
#   bundle_hash     — hash of the recipe's config in mcp-recipes/<name>.json
# The hash function must match the one in the MCP merge Python (stable sort,
# compact separators) so a recipe that hasn't actually changed produces the
# same hash on each install.

def mcp_config_hash(config):
    payload = json.dumps(config, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()

# Load settings.local.json (may be absent if the user never ran --with-mcps).
mcp_servers_current = {}
if os.path.exists(settings_local_path):
    try:
        with open(settings_local_path) as f:
            sl = json.load(f)
        mcp_servers_current = sl.get("mcpServers", {}) or {}
    except json.JSONDecodeError:
        # Malformed settings.local.json — surface as warning, treat as empty so
        # the rest of the upgrade can proceed.
        print(f"  warn: {settings_local_path} is not valid JSON — treating as empty for MCP diff")

# Index bundle recipes for fast lookup.
bundle_recipes = {}
if os.path.isdir(mcp_recipes_dir):
    for fn in os.listdir(mcp_recipes_dir):
        if not fn.endswith(".json"):
            continue
        try:
            with open(os.path.join(mcp_recipes_dir, fn)) as f:
                recipe = json.load(f)
            name = recipe.get("name")
            if name:
                bundle_recipes[name] = recipe
        except json.JSONDecodeError:
            continue

mcp_up_to_date = []
mcp_safe_updates = []
mcp_local_edits = []
mcp_conflicts = []
mcp_orphans = []
# We don't auto-add MCPs on upgrade — additions are an explicit --with-mcps op.

for installed in manifest.get("mcps_installed", []):
    name = installed["name"]
    installed_hash = installed.get("config_sha256")
    current_config = mcp_servers_current.get(name)
    bundle_recipe = bundle_recipes.get(name)
    current_hash = mcp_config_hash(current_config) if current_config is not None else None
    bundle_hash = mcp_config_hash(bundle_recipe["config"]) if (bundle_recipe and "config" in bundle_recipe) else None

    row = {"name": name, "installed_hash": installed_hash,
           "current_hash": current_hash, "bundle_hash": bundle_hash}

    if bundle_hash is None:
        # Recipe no longer ships in the bundle. The user's entry is still in
        # settings.local.json — they own it; we just stop tracking.
        mcp_orphans.append(row)
        continue
    if current_config is None:
        # Manifest says we installed it, but the entry is gone from
        # settings.local.json (user removed it manually). Drop from tracking.
        mcp_orphans.append({**row, "missing_from_settings": True})
        continue

    if current_hash == bundle_hash:
        mcp_up_to_date.append(row)
    elif current_hash == installed_hash and current_hash != bundle_hash:
        mcp_safe_updates.append(row)
    elif current_hash != installed_hash and installed_hash == bundle_hash:
        mcp_local_edits.append(row)
    else:
        mcp_conflicts.append(row)

# ----- Print plan ------------------------------------------------------------
def header(title, rows):
    if not rows:
        return
    print(f"  {title} ({len(rows)})")
    for r in rows[:50]:
        line = f"    {r['path']}"
        cat = r.get("category")
        skill = r.get("skill")
        extras = []
        if cat and cat != "-":
            extras.append(cat)
        if skill:
            extras.append(f"skill={skill}")
        if r.get("renamed_to"):
            extras.append(f"renamed→{r['renamed_to']}")
        if r.get("note"):
            extras.append(r["note"])
        if extras:
            line += "  (" + ", ".join(extras) + ")"
        print(line)
    if len(rows) > 50:
        print(f"    … and {len(rows) - 50} more")
    print("")

manifest_commit = manifest.get("bundle_commit", "unknown")
print(f"  installed bundle commit: {manifest_commit[:12] if manifest_commit != 'unknown' else 'unknown'}")
print(f"  current bundle commit:   {bundle_commit[:12] if bundle_commit != 'unknown' else 'unknown'}")
print(f"  installed at:            {manifest.get('installed_at', '?')}")
# Show a GitHub compare URL when we can — quick way to view exactly what
# changed in the bundle between install and now.
if (bundle_gh_remote
    and manifest_commit not in ("", "unknown")
    and bundle_commit not in ("", "unknown")
    and manifest_commit != bundle_commit):
    print(f"  changes between them:    https://github.com/{bundle_gh_remote}/compare/{manifest_commit}...{bundle_commit}")
print("")

header("Up to date (no action needed):", up_to_date)
header("Safe to update (no local edits, bundle has new content):", safe_updates)
header("Locally edited (left alone — your changes win):", local_edits)
header("Conflict (both local AND bundle changed — default SKIP, --force-conflicts to overwrite):", conflicts)
header("Out of scope (manifest tracks, current --features doesn't include):", out_of_scope)
header("Retired upstream (bundle no longer ships these files):", [{"path": o["path"], "type": o["type"]} for o in orphans])
header("Would add (new in bundle, fits current --features):", additions)

# Renames get their own section so users can see what's moving where. Apply
# treats them as (delete old, write new) atomic pairs.
def rename_header(title, rows):
    if not rows:
        return
    print(f"  {title} ({len(rows)})")
    for r in rows[:50]:
        note = ""
        if r.get("note"):
            note = f"  [{r['note']}]"
        print(f"    {r['path']} → {r['renamed_to']}{note}")
    if len(rows) > 50:
        print(f"    … and {len(rows) - 50} more")
    print("")

rename_header("Renames — safe (no local edits to the old path):", renames_safe)
rename_header("Renames — conflict (local edit at old path OR target path already exists; --force-conflicts to apply anyway):", renames_conflict)

# MCP plan section — only emit if there's anything to say (manifest has MCPs).
mcp_total_tracked = (len(mcp_up_to_date) + len(mcp_safe_updates) +
                     len(mcp_local_edits) + len(mcp_conflicts) + len(mcp_orphans))
if mcp_total_tracked > 0:
    def mcp_header(title, rows):
        if not rows:
            return
        print(f"  {title} ({len(rows)})")
        for r in rows:
            note = ""
            if r.get("missing_from_settings"):
                note = " — entry was removed from settings.local.json"
            print(f"    {r['name']}{note}")
        print("")

    print("MCP entries in .claude/settings.local.json:")
    print("")
    mcp_header("Up to date:", mcp_up_to_date)
    mcp_header("Safe to update (recipe changed upstream, no local edit):", mcp_safe_updates)
    mcp_header("Locally edited (you customized this entry — left alone):", mcp_local_edits)
    mcp_header("Conflict (you edited AND recipe changed — default SKIP, --force-conflicts to overwrite):", mcp_conflicts)
    mcp_header("Orphan (recipe no longer in bundle, or entry removed from settings.local.json):", mcp_orphans)

# Summary line
print(f"==> Plan: {len(safe_updates)} safe update(s), {len(conflicts)} conflict(s),")
print(f"          {len(orphans)} orphan(s), {len(additions)} addition(s),")
print(f"          {len(local_edits)} locally-edited (untouched), {len(up_to_date)} up to date.")
if renames_safe or renames_conflict:
    print(f"          Renames: {len(renames_safe)} safe, {len(renames_conflict)} conflict.")
if mcp_total_tracked > 0:
    print(f"          MCPs: {len(mcp_safe_updates)} safe update(s), {len(mcp_conflicts)} conflict(s),")
    print(f"                {len(mcp_orphans)} orphan(s), {len(mcp_local_edits)} locally-edited,")
    print(f"                {len(mcp_up_to_date)} up to date.")
print("")

if not APPLY:
    print("This is a plan-only preview. No files have been written.")
    print("Re-run with --apply to execute (add --force-conflicts / --prune to opt into the riskier rows).")
    sys.exit(0)

# ----- Apply phase -----------------------------------------------------------
# Skip safe_updates that target never-auto-update types (template / settings) —
# the classifier already routes them to local_edits, but be defensive.
def is_never_auto(row):
    return row.get("type") in ("template", "settings")

actions = []  # list of (kind, row) where kind ∈ {"update","add","delete","rename"}
for r in safe_updates:
    if is_never_auto(r):
        continue
    actions.append(("update", r))
if FORCE_CONFLICTS:
    for r in conflicts:
        if is_never_auto(r):
            continue
        actions.append(("update", r))
skipped_conflicts = 0 if FORCE_CONFLICTS else len([c for c in conflicts if not is_never_auto(c)])
if PRUNE:
    for r in orphans:
        actions.append(("delete", r))
    for r in out_of_scope:
        actions.append(("delete", r))
deleted_count_plan = sum(1 for kind, _ in actions if kind == "delete")
for r in additions:
    actions.append(("add", r))

# Renames — always-safe ones execute under --apply; conflict ones need --force-conflicts.
for r in renames_safe:
    actions.append(("rename", r))
if FORCE_CONFLICTS:
    for r in renames_conflict:
        actions.append(("rename", r))
skipped_rename_conflicts = 0 if FORCE_CONFLICTS else len(renames_conflict)

print(f"==> Applying {len(actions)} action(s)" + (" [DRY RUN]" if DRY_RUN else "") + "...")

written = 0
deleted = 0
for kind, r in actions:
    rel = r["path"]
    dst = os.path.join(target_root, rel)
    if kind in ("update", "add"):
        src = bundle_source_for(rel)
        if not os.path.exists(src):
            # Shouldn't happen — bundle path should exist for in-scope items.
            print(f"  warn: bundle source missing, skipping: {src}")
            continue
        if DRY_RUN:
            print(f"  [dry-run] would {kind}: {rel}")
        else:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            written += 1
    elif kind == "delete":
        if not os.path.exists(dst):
            # Already gone (user may have deleted manually). Manifest will still drop it.
            print(f"  note: already absent on disk: {rel}")
        elif DRY_RUN:
            print(f"  [dry-run] would delete: {rel}")
        else:
            os.remove(dst)
            deleted += 1
            # Clean up now-empty parent dirs we own (under .claude). Don't
            # touch the user's project root.
            parent = os.path.dirname(dst)
            owned_root = os.path.join(target_root, ".claude")
            while parent.startswith(owned_root) and parent != owned_root:
                try:
                    if not os.listdir(parent):
                        os.rmdir(parent)
                        parent = os.path.dirname(parent)
                    else:
                        break
                except OSError:
                    break
    elif kind == "rename":
        # Move file from r["path"] (old) → r["renamed_to"] (new). Write the
        # bundle's content at the new path; delete the old.
        new_rel = r["renamed_to"]
        new_dst = os.path.join(target_root, new_rel)
        old_dst = os.path.join(target_root, rel)
        src = bundle_source_for(new_rel)
        if not os.path.exists(src):
            print(f"  warn: bundle source missing for rename target, skipping: {src}")
            continue
        if DRY_RUN:
            print(f"  [dry-run] would rename: {rel} → {new_rel}")
        else:
            os.makedirs(os.path.dirname(new_dst), exist_ok=True)
            shutil.copy2(src, new_dst)
            written += 1
            if os.path.exists(old_dst):
                os.remove(old_dst)
                deleted += 1
                # Clean up empty parents under .claude/ only.
                parent = os.path.dirname(old_dst)
                owned_root = os.path.join(target_root, ".claude")
                while parent.startswith(owned_root) and parent != owned_root:
                    try:
                        if not os.listdir(parent):
                            os.rmdir(parent)
                            parent = os.path.dirname(parent)
                        else:
                            break
                    except OSError:
                        break

# ----- MCP apply -------------------------------------------------------------
# Decide which MCP entries to mutate. Same model as files:
#   - safe_updates: always under APPLY
#   - conflicts: only under --force-conflicts
#   - orphans: only under --prune (removes entry from settings.local.json AND manifest)
mcp_updates = list(mcp_safe_updates)
if FORCE_CONFLICTS:
    mcp_updates.extend(mcp_conflicts)
mcp_skipped_conflicts = 0 if FORCE_CONFLICTS else len(mcp_conflicts)
mcp_deletions = []
if PRUNE:
    mcp_deletions = list(mcp_orphans)

# Tracking: what manifest entries to drop, what new entries to record.
mcp_dropped_names = set()       # names removed under --prune
mcp_refreshed = {}              # name → fresh config_sha256 to write into manifest
mcp_written = 0
mcp_removed = 0

if mcp_updates or mcp_deletions:
    # Reload settings.local.json fresh — we may need to mutate it.
    sl_data = {}
    if os.path.exists(settings_local_path):
        try:
            with open(settings_local_path) as f:
                sl_data = json.load(f)
        except json.JSONDecodeError:
            print(f"  warn: cannot mutate {settings_local_path} — not valid JSON; skipping MCP apply")
            mcp_updates = []
            mcp_deletions = []
    sl_servers = sl_data.setdefault("mcpServers", {}) if sl_data is not None else {}

    for row in mcp_updates:
        name = row["name"]
        bundle_recipe = bundle_recipes.get(name)
        if not bundle_recipe or "config" not in bundle_recipe:
            continue
        new_config = bundle_recipe["config"]
        if DRY_RUN:
            print(f"  [dry-run] would update MCP: {name}")
        else:
            sl_servers[name] = new_config
            mcp_refreshed[name] = mcp_config_hash(new_config)
            mcp_written += 1

    for row in mcp_deletions:
        name = row["name"]
        if DRY_RUN:
            print(f"  [dry-run] would prune MCP: {name}")
        else:
            sl_servers.pop(name, None)
            mcp_dropped_names.add(name)
            mcp_removed += 1

    if not DRY_RUN and (mcp_written or mcp_removed):
        # Write settings.local.json back. Preserve every other top-level key.
        os.makedirs(os.path.dirname(settings_local_path), exist_ok=True)
        with open(settings_local_path, "w") as f:
            json.dump(sl_data, f, indent=2)
            f.write("\n")

if DRY_RUN:
    print(f"==> [DRY RUN] {len(actions)} file action(s) + {len(mcp_updates) + len(mcp_deletions)} MCP action(s) would run; 0 written.")
    if skipped_conflicts:
        print(f"    {skipped_conflicts} file conflict(s) would be SKIPPED — re-run with --force-conflicts to overwrite.")
    if skipped_rename_conflicts:
        print(f"    {skipped_rename_conflicts} rename conflict(s) would be SKIPPED — re-run with --force-conflicts to apply.")
    if mcp_skipped_conflicts:
        print(f"    {mcp_skipped_conflicts} MCP conflict(s) would be SKIPPED — re-run with --force-conflicts to overwrite.")
    sys.exit(0)

# ----- Re-build manifest from current disk state -----------------------------
def sha256_path(p):
    if not os.path.exists(p):
        return None
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

# Set of rel_paths we just deleted (under --prune OR via the old side of a
# rename) — exclude from new manifest.
deleted_paths = set()
renamed_to_paths = []   # (new_path, src_row) — new entries to add after carry-forward
for kind, r in actions:
    if kind == "delete":
        deleted_paths.add(r["path"])
    elif kind == "rename":
        deleted_paths.add(r["path"])         # old path is gone
        renamed_to_paths.append((r["renamed_to"], r))

# Start by carrying every manifest entry forward UNLESS we deleted it.
# Then layer additions on top. For each carried entry, recompute hash from disk.
new_files = []
seen_paths = set()
for entry in manifest.get("files", []):
    rel = entry["path"]
    if rel in deleted_paths:
        continue
    abs_p = os.path.join(target_root, rel)
    type_ = entry.get("type", "rule")
    if type_ == "gitignore-block":
        # Carry forward unchanged — bash install path manages this block separately.
        new_files.append({
            "path": rel,
            "type": "gitignore-block",
            "category": entry.get("category", "-"),
            "sha256": None,
        })
        seen_paths.add(rel)
        continue
    if not os.path.exists(abs_p):
        # File vanished between plan and apply (or was deleted manually). Drop it.
        continue
    e_out = {
        "path": rel,
        "type": type_,
        "category": entry.get("category", "-"),
        "sha256": sha256_path(abs_p),
    }
    if "skill" in entry:
        e_out["skill"] = entry["skill"]
    new_files.append(e_out)
    seen_paths.add(rel)

# Additions that just landed → record them.
for kind, r in actions:
    if kind != "add":
        continue
    rel = r["path"]
    if rel in seen_paths:
        continue   # already carried forward (shouldn't happen for additions)
    abs_p = os.path.join(target_root, rel)
    if not os.path.exists(abs_p):
        continue
    e_out = {
        "path": rel,
        "type": r.get("type", "rule"),
        "category": r.get("category", "-"),
        "sha256": sha256_path(abs_p),
    }
    if r.get("skill"):
        e_out["skill"] = r["skill"]
    new_files.append(e_out)
    seen_paths.add(rel)

# Renames — record the NEW path with the bundle's metadata (skill name comes
# from the rewritten path's skill dir). Carry-forward already dropped the old
# entry because we added it to deleted_paths above.
for new_rel, src_row in renamed_to_paths:
    if new_rel in seen_paths:
        continue
    abs_p = os.path.join(target_root, new_rel)
    if not os.path.exists(abs_p):
        continue
    bundle_meta = bundle_all.get(new_rel)
    type_ = bundle_meta[0] if bundle_meta else src_row.get("type", "rule")
    cat   = bundle_meta[1] if bundle_meta else src_row.get("category", "-")
    e_out = {
        "path": new_rel,
        "type": type_,
        "category": cat,
        "sha256": sha256_path(abs_p),
    }
    # If the new path is under a skill dir, infer the new skill name from it.
    if new_rel.startswith(".claude/skills/"):
        parts = new_rel.split("/")
        if len(parts) >= 3:
            e_out["skill"] = parts[2]
    new_files.append(e_out)
    seen_paths.add(new_rel)

# Rebuild mcps_installed from the apply outcome:
#   - drop entries pruned under --prune
#   - update config_sha256 for entries we just refreshed (safe-update / force-conflicts)
#   - carry every other entry forward unchanged
new_mcps_installed = []
for installed in manifest.get("mcps_installed", []):
    name = installed["name"]
    if name in mcp_dropped_names:
        continue
    if name in mcp_refreshed:
        new_mcps_installed.append({"name": name, "config_sha256": mcp_refreshed[name]})
    else:
        new_mcps_installed.append(installed)

new_manifest = {
    "schema_version": 2,
    "installed_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "bundle_commit": bundle_commit if bundle_commit else "unknown",
    "selection": {
        "platform": platform,
        "apple_language": apple_lang,
        # Carried forward from the existing manifest — --apple-platforms only
        # affects the visionOS rule via the `spatial` feature category, whose
        # effect is already captured in features_resolved, so re-running upgrade
        # preserves the recorded targets. Re-install to change them.
        "apple_platforms_input": manifest.get("selection", {}).get("apple_platforms_input", ""),
        "apple_platforms_resolved": manifest.get("selection", {}).get("apple_platforms_resolved", []),
        "features_input": features,
        "features_resolved": manifest.get("selection", {}).get("features_resolved", []),
        "agents_input": agents_input,
        "agents_resolved": agents_resolved,
    },
    "files": new_files,
    "mcps_installed": new_mcps_installed,
}

with open(manifest_path, "w") as f:
    json.dump(new_manifest, f, indent=2)
    f.write("\n")

# ----- Apply summary ---------------------------------------------------------
print(f"==> Apply complete: {written} file(s) written, {deleted} deleted.")
if mcp_written or mcp_removed:
    print(f"    MCPs: {mcp_written} entry(ies) updated, {mcp_removed} pruned.")
if mcp_skipped_conflicts:
    print(f"    {mcp_skipped_conflicts} MCP conflict(s) SKIPPED — re-run with --force-conflicts to overwrite.")
if skipped_conflicts:
    print(f"    {skipped_conflicts} conflict(s) SKIPPED — re-run with --force-conflicts to overwrite.")
print(f"==> Manifest refreshed: {manifest_path}")
