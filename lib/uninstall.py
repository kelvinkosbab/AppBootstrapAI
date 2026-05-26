#!/usr/bin/env python3
"""Reverse-of-install for AppBootstrapAI.

Walks the manifest at $TARGET/.claude/.appbootstrap-manifest.json, classifies
each tracked file by safety, removes the safe ones, optionally cleans up the
locally-edited / user-protected ones, removes matching MCP entries from
settings.local.json, strips the AppBootstrapAI gitignore block, and deletes
the manifest itself.

Args:
    sys.argv[1] — manifest_path        (absolute)
    sys.argv[2] — target_root          (absolute install root)
    sys.argv[3] — settings_local_path  (absolute; may not exist)
    sys.argv[4] — force_flag           ("true" → delete user-edited files too)
    sys.argv[5] — purge_flag           ("true" → delete CLAUDE.md / settings.json too)
    sys.argv[6] — keep_mcps_flag       ("true" → leave settings.local.json mcpServers alone)
    sys.argv[7] — dry_run_flag         ("true" → preview only)

Output (stdout, human-readable):
    Plan sections + summary lines.

Exit codes:
    0 — uninstall completed (or dry-run preview).
"""
import hashlib
import json
import os
import sys


def sha256_path(path: str):
    """sha256 hex digest of a file's contents, or None if the file is missing."""
    if not os.path.exists(path):
        return None
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def mcp_config_hash(config) -> str:
    """Stable sha256 of an MCP recipe's config — must match mcp_merge.py."""
    payload = json.dumps(config, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()


def section(title: str, rows) -> None:
    """Print a human-readable section with up to 50 rows."""
    if not rows:
        return
    print(f"  {title} ({len(rows)})")
    for r in rows[:50]:
        path = r["path"] if isinstance(r, dict) else r
        print(f"    {path}")
    if len(rows) > 50:
        print(f"    … and {len(rows) - 50} more")
    print("")


def cleanup_empty_parents(deleted_path: str, target_root: str) -> None:
    """Remove now-empty parent directories under .claude/ only.

    Walks upward from `deleted_path`'s parent. Stops when it hits a non-empty
    directory or when it crosses out of the .claude/ subtree (never touches
    the user's project root).
    """
    parent = os.path.dirname(deleted_path)
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


def main() -> int:
    (manifest_path, target_root, settings_local_path,
     force_flag, purge_flag, keep_mcps_flag, dry_run_flag) = sys.argv[1:8]

    FORCE     = (force_flag      == "true")
    PURGE     = (purge_flag      == "true")
    KEEP_MCPS = (keep_mcps_flag  == "true")
    DRY_RUN   = (dry_run_flag    == "true")

    with open(manifest_path) as f:
        manifest = json.load(f)

    # ----- Classify each tracked file --------------------------------------
    safe_delete = []     # current hash matches installed hash → delete
    user_edited = []     # current hash differs → keep unless --force
    user_protected = []  # template / settings → keep unless --purge
    missing = []         # already gone from disk

    for entry in manifest.get("files", []):
        rel = entry["path"]
        type_ = entry.get("type", "rule")
        installed_hash = entry.get("sha256")
        abs_path = os.path.join(target_root, rel)

        if type_ == "gitignore-block":
            continue  # handled separately at the end

        if not os.path.exists(abs_path):
            missing.append(rel)
            continue

        if type_ in ("template", "settings"):
            user_protected.append({"path": rel, "type": type_})
            continue

        current_hash = sha256_path(abs_path)
        if installed_hash is None or current_hash == installed_hash:
            safe_delete.append({"path": rel, "type": type_})
        else:
            user_edited.append({"path": rel, "type": type_})

    # ----- Print plan ------------------------------------------------------
    print("")
    section("Will delete (unchanged since install):", safe_delete)
    section("Locally edited — keep unless --force:", user_edited)
    section("User-protected (CLAUDE.md / settings.json) — keep unless --purge:", user_protected)
    section("Already absent on disk (will drop from manifest):", missing)

    # ----- File deletions --------------------------------------------------
    to_delete = list(safe_delete)
    if FORCE:
        to_delete.extend(user_edited)
    if PURGE:
        to_delete.extend(user_protected)

    print(f"==> Deleting {len(to_delete)} file(s)"
          + (" [DRY RUN]" if DRY_RUN else "") + "...")
    deleted_count = 0
    for r in to_delete:
        rel = r["path"] if isinstance(r, dict) else r
        abs_path = os.path.join(target_root, rel)
        if not os.path.exists(abs_path):
            continue
        if DRY_RUN:
            print(f"  [dry-run] would delete: {rel}")
        else:
            os.remove(abs_path)
            deleted_count += 1
            cleanup_empty_parents(abs_path, target_root)

    # ----- MCP cleanup -----------------------------------------------------
    mcps_removed = 0
    mcps_skipped = []   # names left in settings.local.json (modified or missing recipe)

    if not KEEP_MCPS and manifest.get("mcps_installed"):
        sl_data = {}
        if os.path.exists(settings_local_path):
            try:
                with open(settings_local_path) as f:
                    sl_data = json.load(f)
            except json.JSONDecodeError:
                print(f"  warn: {settings_local_path} not valid JSON; "
                      f"skipping MCP cleanup")
                sl_data = None
        if sl_data is not None:
            sl_servers = sl_data.get("mcpServers", {}) or {}
            before = dict(sl_servers)
            for installed in manifest["mcps_installed"]:
                name = installed["name"]
                installed_hash = installed.get("config_sha256")
                current_config = sl_servers.get(name)
                if current_config is None:
                    continue   # already removed by user
                current_hash = mcp_config_hash(current_config)
                if current_hash == installed_hash or FORCE:
                    if DRY_RUN:
                        print(f"  [dry-run] would remove MCP: {name}")
                    else:
                        del sl_servers[name]
                        mcps_removed += 1
                else:
                    mcps_skipped.append(name)
            if not DRY_RUN and sl_servers != before:
                if sl_servers:
                    sl_data["mcpServers"] = sl_servers
                else:
                    # mcpServers ended up empty → drop the key. Other top-level
                    # keys (customField, permissions, etc.) stay untouched.
                    sl_data.pop("mcpServers", None)
                with open(settings_local_path, "w") as f:
                    json.dump(sl_data, f, indent=2)
                    f.write("\n")

    # ----- .gitignore block + manifest removal -----------------------------
    gitignore_path = os.path.join(target_root, ".gitignore")
    gitignore_stripped = False
    if os.path.exists(gitignore_path) and not DRY_RUN:
        with open(gitignore_path) as f:
            lines = f.read().splitlines()
        out_lines = []
        in_block = False
        for line in lines:
            if line.startswith("# --- AppBootstrapAI ("):
                in_block = True
                # Drop a leading blank line if present so we don't accumulate
                # trailing whitespace across repeated install/uninstall cycles.
                while out_lines and out_lines[-1] == "":
                    out_lines.pop()
                continue
            if in_block and line == "# --- end AppBootstrapAI ---":
                in_block = False
                continue
            if not in_block:
                out_lines.append(line)
        new_content = "\n".join(out_lines)
        if new_content and not new_content.endswith("\n"):
            new_content += "\n"
        with open(gitignore_path, "w") as f:
            f.write(new_content)
        gitignore_stripped = True
    elif os.path.exists(gitignore_path):
        # dry-run path: just check if there's a block to strip
        with open(gitignore_path) as f:
            if "# --- AppBootstrapAI (" in f.read():
                print("  [dry-run] would strip .gitignore block")

    if not DRY_RUN:
        if os.path.exists(manifest_path):
            os.remove(manifest_path)
            # Try to remove .claude/ if now empty.
            claude_dir = os.path.dirname(manifest_path)
            try:
                if not os.listdir(claude_dir):
                    os.rmdir(claude_dir)
            except OSError:
                pass

    # ----- Summary ---------------------------------------------------------
    print("")
    if DRY_RUN:
        print(f"==> [DRY RUN] {len(to_delete)} file(s) would be deleted; "
              f"{mcps_removed} MCP entry(ies) would be removed.")
        if user_edited and not FORCE:
            print(f"    {len(user_edited)} locally-edited file(s) would be KEPT "
                  f"— re-run with --force to remove.")
        if user_protected and not PURGE:
            print(f"    {len(user_protected)} user-protected file(s) "
                  f"(CLAUDE.md / settings.json) would be KEPT "
                  f"— re-run with --purge to remove.")
        if mcps_skipped:
            print(f"    {len(mcps_skipped)} MCP entry(ies) would be KEPT "
                  f"(modified): {', '.join(mcps_skipped)}")
    else:
        print(f"==> Uninstall complete: {deleted_count} file(s) deleted, "
              f"{mcps_removed} MCP entry(ies) removed.")
        if gitignore_stripped:
            print(f"    Stripped AppBootstrapAI block from {gitignore_path}")
        if user_edited and not FORCE:
            print(f"    Kept {len(user_edited)} locally-edited file(s) "
                  f"— re-run with --force to remove.")
        if user_protected and not PURGE:
            print(f"    Kept {len(user_protected)} user-protected file(s) "
                  f"(CLAUDE.md / settings.json) — re-run with --purge to remove.")
        if mcps_skipped:
            print(f"    Kept {len(mcps_skipped)} modified MCP entry(ies): "
                  f"{', '.join(mcps_skipped)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
