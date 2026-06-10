# shellcheck shell=bash
# AppBootstrapAI installer — install mode.
#
# Sourced from install.sh when ACTION=install (the default). The biggest single
# section in the package: TARGET resolution + dir check, install-header echo,
# record_install / record_install_meta helpers, INSTALLED_FILES + INSTALLED_MCPS_*
# globals, per-agent install paths (Claude rules+skills+settings+CLAUDE.md;
# Copilot / Gemini / Codex concat files via install_agent_concat helper; Cursor
# per-rule .mdc files), .gitignore append, write_manifest function (v2 schema
# with hashes + bundle_commit + selection + mcps_installed). The actual MCP
# merge + manifest write happen later via lib/install_mcps.sh.

# --- Install mode -------------------------------------------------------------

# Missing target: create it under --new (new-project bootstrap), else error.
# The error guards against a typo'd path silently creating a stray directory.
if [[ ! -d "$TARGET" ]]; then
    if [[ "$NEW_PROJECT" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] would create directory $TARGET"
        else
            mkdir -p "$TARGET"
            echo "--> Created $TARGET"
        fi
    else
        echo "error: target directory does not exist: $TARGET" >&2
        echo "       Pass --new to create it (and git init a fresh repo), e.g.:" >&2
        echo "         install.sh $TARGET --platform apple --new" >&2
        exit 1
    fi
fi

# Resolve to an absolute path. Tolerate a not-yet-created dir under
# --new + --dry-run (can't cd into it) by composing the path manually.
if [[ -d "$TARGET" ]]; then
    TARGET="$(cd "$TARGET" && pwd)"
else
    case "$TARGET" in
        /*) : ;;
        *)  TARGET="$PWD/$TARGET" ;;
    esac
fi

# --new: git init a fresh repo (only when the dir isn't already under git).
if [[ "$NEW_PROJECT" == "true" && "$DRY_RUN" != "true" ]]; then
    if [[ ! -d "$TARGET/.git" ]] && command -v git >/dev/null 2>&1; then
        git -C "$TARGET" init -q && echo "--> git init $TARGET"
    fi
fi

# Already-managed target: refuse a plain re-install and steer to --upgrade,
# unless --force. Re-running install only adds missing files AND rewrites the
# manifest — which resets the --upgrade baseline (a silent footgun).
MANAGED_MANIFEST="$TARGET/.claude/.appbootstrap-manifest.json"
if [[ -f "$MANAGED_MANIFEST" && "$FORCE" != "true" ]]; then
    echo "==> $TARGET already has an AppBootstrapAI install." >&2
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$MANAGED_MANIFEST" <<'PY' >&2 || true
import json, sys
try:
    m = json.load(open(sys.argv[1]))
    print(f"    installed at:  {m.get('installed_at', '?')}")
    bc = m.get("bundle_commit", "unknown")
    print(f"    bundle commit: {bc[:12] if bc != 'unknown' else 'unknown'}")
except Exception:
    pass
PY
    fi
    echo "    Re-running install only ADDS missing files and rewrites the manifest," >&2
    echo "    which resets the --upgrade baseline. To review/apply bundle updates:" >&2
    echo "      install.sh \"$TARGET\" --upgrade           # preview the plan" >&2
    echo "      install.sh \"$TARGET\" --upgrade --apply   # execute it" >&2
    echo "    To re-install anyway (adds any missing files), pass --force." >&2
    exit 1
fi

echo "==> Installing AppBootstrapAI into $TARGET"
if [[ "$PLATFORM_AUTODETECTED" == "true" ]]; then
    echo "    platform: $PLATFORM (auto-detected)   apple-language: $APPLE_LANG"
    [[ -n "$DETECTED_APPLE_SIGNALS"   ]] && echo "      apple signals:   $DETECTED_APPLE_SIGNALS"
    [[ -n "$DETECTED_ANDROID_SIGNALS" ]] && echo "      android signals: $DETECTED_ANDROID_SIGNALS"
    echo "      (override with --platform apple|android|both)"
elif [[ "$PLATFORM_AUTODETECT_FALLBACK" == "true" ]]; then
    echo "    platform: $PLATFORM (auto-detect found no project files → fallback)   apple-language: $APPLE_LANG"
    echo "      (override with --platform apple|android|both)"
else
    echo "    platform: $PLATFORM   apple-language: $APPLE_LANG"
fi
[[ "$PLATFORM" != "android" ]] && echo "    apple platforms: $SELECTED_APPLE_PLATFORMS"
echo "    features: $FEATURES_INPUT  ($SELECTED_FEATURES)"
echo "    agents:   $SELECTED_AGENTS"
if [[ "$DRY_RUN" == "true" ]]; then
    echo "==> [DRY RUN] No files will be written. Re-run without --dry-run to apply."
fi

# Track installed files for the manifest.
# Entry format: rel_path|type|category|sha256|skill_name
#   rel_path    — path relative to TARGET (e.g. ".claude/rules/foo.md")
#   type        — "rule" | "skill-file" | "settings" | "template" | "gitignore-block"
#   category    — feature category or "-" for uncategorized
#   sha256      — content hash, or empty for non-content entries (gitignore-block)
#   skill_name  — only set for skill-file entries; empty otherwise
#
# Use record_install for single files (hash is computed from source path).
# Use record_install_meta for non-content entries (gitignore block).
INSTALLED_FILES=()
record_install() {
    local rel_path="$1" type_="$2" category="$3" source_path="$4" skill_name="${5:-}"
    local hash
    hash="$(sha256_file "$source_path")"
    INSTALLED_FILES+=("$rel_path|$type_|$category|$hash|$skill_name")
}
record_install_meta() {
    # Non-content entries: no source file to hash.
    local rel_path="$1" type_="$2" category="$3"
    INSTALLED_FILES+=("$rel_path|$type_|$category||")
}

# Track MCP entries that were added/skipped by --with-mcps. Populated by
# install_mcps_now() (called late in the install flow). Used to print setup
# notes and to extend the manifest.
INSTALLED_MCPS_ADDED=()
# shellcheck disable=SC2034   # read by lib/install_mcps.sh
INSTALLED_MCPS_SKIPPED=()

# The manifest lives at .claude/.appbootstrap-manifest.json regardless of which
# agents are selected. Ensure the dir exists so the late-stage manifest write
# can land even on a non-Claude-only install (e.g., --agents copilot).
act "create $TARGET/.claude (for manifest)" mkdir -p "$TARGET/.claude"

# ----- Claude agent install (default) ----------------------------------------
if agents_has claude; then
    act "create $TARGET/.claude/rules"  mkdir -p "$TARGET/.claude/rules"
    act "create $TARGET/.claude/skills" mkdir -p "$TARGET/.claude/skills"

    # Skills — copy each individually based on platform/language/features filter.
    # Each file inside the skill directory gets its own manifest entry with a hash,
    # so a local edit to one reference doesn't block upstream updates to siblings.
    if should_install_any_skills; then
        echo "--> Copying skills (.claude/skills/)"
        shopt -s nullglob
        for d in "$SCRIPT_DIR/.claude/skills/"*/; do
            name="$(basename "$d")"
            if should_install_skill "$name"; then
                cat="$(file_category "$name")"
                [[ -z "$cat" ]] && cat="-"
                act "copy skill $name" cp -R "$d" "$TARGET/.claude/skills/$name"
                # Walk every file inside the source skill dir; record_install each
                # so the manifest has a per-file hash. `find -type f` includes
                # nested references/, agents/, assets/ — exactly what we copied.
                while IFS= read -r -d '' src_file; do
                    # Strip the SCRIPT_DIR prefix so rel_path is target-relative.
                    rel_path="${src_file#"$SCRIPT_DIR"/}"
                    record_install "$rel_path" "skill-file" "$cat" "$src_file" "$name"
                done < <(find "$d" -type f -print0)
            fi
        done
    else
        echo "--> Skipping skills (not in scope for current selection)"
    fi

    # Rules → .claude/rules/.
    echo "--> Copying rules (.claude/rules/)"
    shopt -s nullglob
    for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
        name="$(basename "$f")"
        if should_install_rule "$name"; then
            cat="$(file_category "$name")"
            [[ -z "$cat" ]] && cat="-"
            act "copy rule $name" cp "$f" "$TARGET/.claude/rules/$name"
            record_install ".claude/rules/$name" "rule" "$cat" "$f"
        fi
    done

    # settings.json — never overwrite.
    if [[ ! -f "$TARGET/.claude/settings.json" ]]; then
        act "copy settings.json" cp "$SCRIPT_DIR/.claude/settings.json" "$TARGET/.claude/settings.json"
        record_install ".claude/settings.json" "settings" "-" "$SCRIPT_DIR/.claude/settings.json"
    else
        echo "--> Skipping settings.json (already exists — merge manually)"
    fi

    # CLAUDE.md — render from the platform-appropriate template, never overwrite.
    case "$PLATFORM" in
        apple)   TEMPLATE="$SCRIPT_DIR/templates/CLAUDE.template.apple.md"   ;;
        android) TEMPLATE="$SCRIPT_DIR/templates/CLAUDE.template.android.md" ;;
        both)    TEMPLATE="$SCRIPT_DIR/templates/CLAUDE.template.md"         ;;
    esac

    if [[ -f "$TARGET/CLAUDE.md" ]]; then
        echo "--> Skipping CLAUDE.md (already exists — merge manually)"
    elif [[ ! -f "$TEMPLATE" ]]; then
        echo "--> Skipping CLAUDE.md (template missing: $TEMPLATE)"
    else
        act "create CLAUDE.md from $(basename "$TEMPLATE")" cp "$TEMPLATE" "$TARGET/CLAUDE.md"
        record_install "CLAUDE.md" "template" "core" "$TEMPLATE"
    fi
fi

# ----- Non-Claude agents ------------------------------------------------------
#
# Each non-Claude agent gets its own set of files derived from the in-scope
# rules. Skills are skipped (Claude-only). Existing files are NEVER
# overwritten — same policy as CLAUDE.md / settings.json.
#
# install_agent_concat <agent_tag> <rel_path> <banner_purpose>
# Writes a deterministic concat to <TARGET>/<rel_path> via concat_in_scope_rules.
install_agent_concat() {
    local agent_tag="$1" rel_path="$2" banner_purpose="$3"
    local dst="$TARGET/$rel_path"
    if [[ -f "$dst" ]]; then
        echo "--> Skipping $rel_path (already exists — merge manually)"
        return
    fi
    # Stage the concat in a temp file so we can:
    #   - hash it
    #   - record it in the manifest with that hash
    #   - move it into place (or skip under dry-run)
    local tmp; tmp="$(mktemp)"
    concat_in_scope_rules "$banner_purpose" > "$tmp"
    act "create $rel_path (concat of in-scope rules)" mkdir -p "$(dirname "$dst")"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] would write $rel_path ($(wc -l < "$tmp" | tr -d ' ') lines)"
        # Still record under dry-run so the count is accurate.
        record_install "$rel_path" "agent-file-$agent_tag" "-" "$tmp"
    else
        mv "$tmp" "$dst"
        record_install "$rel_path" "agent-file-$agent_tag" "-" "$dst"
    fi
    rm -f "$tmp"
}

if agents_has copilot; then
    echo "--> Installing for GitHub Copilot (.github/copilot-instructions.md)"
    install_agent_concat "copilot" ".github/copilot-instructions.md" "GitHub Copilot"
fi

if agents_has gemini; then
    echo "--> Installing for Gemini CLI (GEMINI.md)"
    install_agent_concat "gemini" "GEMINI.md" "Gemini CLI"
fi

if agents_has codex; then
    echo "--> Installing for Codex / generic agents (AGENTS.md)"
    install_agent_concat "codex" "AGENTS.md" "Codex CLI and other AGENTS.md-aware tools"
fi

if agents_has cursor; then
    # Cursor uses per-rule .mdc files under .cursor/rules/. Direct 1:1 with
    # .claude/rules/, just renamed. Each file gets its own manifest entry
    # so upgrade can diff per-rule (like skill-file does for Claude skills).
    echo "--> Installing for Cursor (.cursor/rules/*.mdc)"
    act "create $TARGET/.cursor/rules" mkdir -p "$TARGET/.cursor/rules"
    shopt -s nullglob
    for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
        name="$(basename "$f")"
        if should_install_rule "$name"; then
            mdc_name="${name%.md}.mdc"
            dst="$TARGET/.cursor/rules/$mdc_name"
            if [[ -f "$dst" ]]; then
                echo "    skipping $mdc_name (already exists)"
                continue
            fi
            cat="$(file_category "$name")"
            [[ -z "$cat" ]] && cat="-"
            act "copy cursor rule $mdc_name" cp "$f" "$dst"
            record_install ".cursor/rules/$mdc_name" "agent-file-cursor" "$cat" "$f"
        fi
    done
fi

if agents_has kiro; then
    # Amazon Kiro uses per-rule steering files under .kiro/steering/*.md, with
    # `inclusion: fileMatch` + `fileMatchPattern` frontmatter (see
    # kiro_steering_from_rule in lib/predicates.sh). The frontmatter is rewritten
    # from each rule's globs, so the file is generated — we hash the generated
    # output (like the concat agents), not the source rule.
    echo "--> Installing for Kiro (.kiro/steering/*.md)"
    act "create $TARGET/.kiro/steering" mkdir -p "$TARGET/.kiro/steering"
    shopt -s nullglob
    for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
        name="$(basename "$f")"
        if should_install_rule "$name"; then
            dst="$TARGET/.kiro/steering/$name"
            if [[ -f "$dst" ]]; then
                echo "    skipping $name (already exists)"
                continue
            fi
            cat="$(file_category "$name")"
            [[ -z "$cat" ]] && cat="-"
            if [[ "$DRY_RUN" == "true" ]]; then
                tmp="$(mktemp)"
                kiro_steering_from_rule "$f" > "$tmp"
                echo "[dry-run] would write .kiro/steering/$name"
                record_install ".kiro/steering/$name" "agent-file-kiro" "$cat" "$tmp"
                rm -f "$tmp"
            else
                kiro_steering_from_rule "$f" > "$dst"
                record_install ".kiro/steering/$name" "agent-file-kiro" "$cat" "$dst"
            fi
        fi
    done
fi

# .gitignore — append platform entries, deduped by marker.
GITIGNORE="$TARGET/.gitignore"
MARKER="# --- AppBootstrapAI ($PLATFORM) ---"
if [[ -f "$GITIGNORE" ]] && grep -qF "$MARKER" "$GITIGNORE"; then
    echo "--> Skipping .gitignore (marker already present)"
else
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] would append .gitignore block marked '$MARKER'"
    else
        touch "$GITIGNORE"
        {
            echo ""
            echo "$MARKER"
            if [[ "$PLATFORM" != "android" ]]; then
                cat <<'APPLE'
# Apple / Xcode / SPM
*.DS_Store
*xcuserdata*
DerivedData/
build/
*.ipa
*.dSYM.zip
.build/
.swiftpm/
Package.resolved
Carthage/Build/
fastlane/report.xml
fastlane/test_output
APPLE
            fi
            if [[ "$PLATFORM" != "apple" ]]; then
                cat <<'ANDROID'
# Android / Gradle / Kotlin
.gradle/
build/
*.apk
*.aab
local.properties
keystore.properties
*.jks
*.keystore
.kotlin/
.idea/
*.iml
ANDROID
            fi
            if agents_has claude; then
                echo "# Claude Code local settings"
                echo ".claude/settings.local.json"
                echo ".claude/plans/"
            fi
            if agents_has cursor; then
                echo "# Cursor runtime caches (per-developer; not committed)"
                echo ".cursor/state*"
                echo ".cursor/.cache/"
            fi
            echo "# --- end AppBootstrapAI ---"
        } >> "$GITIGNORE"
        echo "--> Appended recommended .gitignore entries"
    fi
    record_install_meta ".gitignore" "gitignore-block" "-"
fi

# Manifest — records every file the installer wrote (with content hashes,
# under schema v2) so future --upgrade flows can do per-file 3-way diffs:
# installed hash (here) vs. current disk hash vs. bundle hash.
#
# Called at the END of install (after the MCP merge) so mcps_installed reflects
# what actually got written, not what was requested.
MANIFEST_PATH="$TARGET/.claude/.appbootstrap-manifest.json"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

write_manifest() {
    {
        printf '{\n'
        printf '  "schema_version": 2,\n'
        printf '  "installed_at": "%s",\n' "$TIMESTAMP"
        printf '  "bundle_commit": "%s",\n' "$BUNDLE_COMMIT"
        printf '  "selection": {\n'
        printf '    "platform": "%s",\n' "$PLATFORM"
        printf '    "apple_language": "%s",\n' "$APPLE_LANG"
        printf '    "apple_platforms_input": "%s",\n' "$APPLE_PLATFORMS_INPUT"
        printf '    "apple_platforms_resolved": '
        json_string_array "$SELECTED_APPLE_PLATFORMS"
        printf ',\n'
        printf '    "features_input": "%s",\n' "$FEATURES_INPUT"
        printf '    "features_resolved": '
        json_string_array "$SELECTED_FEATURES"
        printf ',\n'
        printf '    "agents_input": "%s",\n' "$AGENTS_INPUT"
        printf '    "agents_resolved": '
        json_string_array "$SELECTED_AGENTS"
        printf '\n  },\n'
        printf '  "files": [\n'
        local first=1 entry path type_ cat_ hash skill hash_field
        for entry in "${INSTALLED_FILES[@]}"; do
            # rel_path|type|category|sha256|skill_name
            IFS='|' read -r path type_ cat_ hash skill <<<"$entry"
            if [[ "$first" -eq 1 ]]; then first=0; else printf ',\n'; fi
            # Emit sha256 as null when empty (gitignore-block); JSON string otherwise.
            if [[ -z "$hash" ]]; then
                hash_field='"sha256": null'
            else
                hash_field=$(printf '"sha256": "%s"' "$hash")
            fi
            # Emit "skill" field only for skill-file entries.
            if [[ -n "$skill" ]]; then
                printf '    {"path": "%s", "type": "%s", "category": "%s", %s, "skill": "%s"}' \
                    "$path" "$type_" "$cat_" "$hash_field" "$skill"
            else
                printf '    {"path": "%s", "type": "%s", "category": "%s", %s}' \
                    "$path" "$type_" "$cat_" "$hash_field"
            fi
        done
        printf '\n  ],\n'
        # mcps_installed — array of {name, config_sha256}. Records what we
        # actually wrote into settings.local.json (not what was requested but
        # skipped because already present).
        printf '  "mcps_installed": ['
        first=1
        # Guard the array expansion — `set -u` + bash 3.x errors on "${arr[@]}"
        # when the array is unset/empty.
        if [[ "${#INSTALLED_MCPS_ADDED[@]}" -gt 0 ]]; then
            local mcp_entry mcp_name mcp_hash
            for mcp_entry in "${INSTALLED_MCPS_ADDED[@]}"; do
                mcp_name="${mcp_entry%%|*}"
                mcp_hash="${mcp_entry#*|}"
                if [[ "$first" -eq 1 ]]; then first=0; printf '\n'; else printf ',\n'; fi
                if [[ -z "$mcp_hash" ]]; then
                    printf '    {"name": "%s", "config_sha256": null}' "$mcp_name"
                else
                    printf '    {"name": "%s", "config_sha256": "%s"}' "$mcp_name" "$mcp_hash"
                fi
            done
        fi
        if [[ "$first" -eq 0 ]]; then printf '\n  '; fi
        printf ']\n'
        printf '}\n'
    } > "$MANIFEST_PATH"
    echo "--> Wrote manifest to $MANIFEST_PATH"
}
