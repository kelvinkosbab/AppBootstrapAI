# shellcheck shell=bash
# AppBootstrapAI installer — --with-mcps install merge.
#
# Sourced from install.sh AFTER the file install path runs. Calls
# lib/mcp_merge.py to update .claude/settings.local.json's mcpServers map
# (idempotent: existing entries are never overwritten), then parses Python's
# machine-readable output back into INSTALLED_MCPS_ADDED / INSTALLED_MCPS_SKIPPED
# arrays (used by write_manifest later) and prints any setup notes the recipes
# carried.

# --- MCP recipes — merge into .claude/settings.local.json -------------------
#
# Each named recipe contributes one entry under "mcpServers". Existing entries
# with the same name are preserved (never overwritten). settings.local.json is
# the right target because MCP configs often carry machine-specific paths /
# tokens and shouldn't be committed; the file is gitignored by the bundle.

if [[ -n "$SELECTED_MCPS" ]]; then
    SETTINGS_LOCAL="$TARGET/.claude/settings.local.json"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] would merge MCP recipes into $SETTINGS_LOCAL: $SELECTED_MCPS"
        for mcp_name in $SELECTED_MCPS; do
            # No actual write happens, so no hash. Record name-only entry; the
            # manifest will record an empty hash for these dry-run rows (they
            # won't be in the real manifest because --dry-run skips the write).
            INSTALLED_MCPS_ADDED+=("$mcp_name|")
        done
    else
        echo "--> Merging MCP recipes into $(basename "$SETTINGS_LOCAL"): $SELECTED_MCPS"
        # JSON merge + per-recipe config_sha256 computation. See lib/mcp_merge.py.
        merge_output="$(python3 "$SCRIPT_DIR/lib/mcp_merge.py" "$SETTINGS_LOCAL" "$MCP_RECIPES_DIR" "$SELECTED_MCPS")"
        # Parse the python output back into bash arrays.
        while IFS= read -r line; do
            case "$line" in
                ADDED:*)
                    # Format: ADDED:name1=hash1,name2=hash2
                    added_csv="${line#ADDED:}"
                    if [[ -n "$added_csv" ]]; then
                        # shellcheck disable=SC2206
                        IFS=',' read -r -a tmp <<<"$added_csv"
                        for entry in "${tmp[@]}"; do
                            # Convert "name=hash" → "name|hash" for our array form.
                            INSTALLED_MCPS_ADDED+=("${entry/=/|}")
                        done
                    fi
                    ;;
                SKIPPED:*)
                    skipped_csv="${line#SKIPPED:}"
                    if [[ -n "$skipped_csv" ]]; then
                        IFS=',' read -r -a tmp <<<"$skipped_csv"
                        for entry in "${tmp[@]}"; do
                            INSTALLED_MCPS_SKIPPED+=("$entry")
                        done
                    fi
                    ;;
            esac
        done <<<"$merge_output"

        if [[ "${#INSTALLED_MCPS_ADDED[@]}" -gt 0 ]]; then
            # Entries are "name|hash" — strip hash for human display.
            added_display=""
            for entry in "${INSTALLED_MCPS_ADDED[@]}"; do
                added_display="$added_display ${entry%%|*}"
            done
            echo "    added:${added_display}"
        fi
        if [[ "${#INSTALLED_MCPS_SKIPPED[@]}" -gt 0 ]]; then
            echo "    skipped (already present): ${INSTALLED_MCPS_SKIPPED[*]}"
        fi

        # Re-print the setup notes verbatim from the python output.
        if echo "$merge_output" | grep -q "^---SETUP---"; then
            echo ""
            echo "==> Setup steps for newly-installed MCPs:"
            current=""
            while IFS= read -r line; do
                case "$line" in
                    ---SETUP---) echo "" ;;
                    NAME:*)
                        current="${line#NAME:}"
                        echo "    $current"
                        ;;
                    HOMEPAGE:*) echo "      (see $(echo "$line" | sed 's|^HOMEPAGE:||'))" ;;
                    STEP:*) echo "      - $(echo "$line" | sed 's|^STEP:||')" ;;
                esac
            done <<<"$merge_output"
        fi
    fi
fi

# Manifest write — runs last so mcps_installed reflects the MCP merge result.
if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] would write manifest ($MANIFEST_PATH, ${#INSTALLED_FILES[@]} entries)"
else
    write_manifest
fi

echo ""
if [[ "$DRY_RUN" == "true" ]]; then
    echo "==> [DRY RUN] Complete. ${#INSTALLED_FILES[@]} file(s) would be installed. Re-run without --dry-run to apply."
else
    echo "==> Done. Next steps:"
    step=1
    if agents_has claude; then
        echo "    $step. Edit $TARGET/CLAUDE.md — fill in the <PLACEHOLDER> sections."
        step=$((step + 1))
    fi
    if agents_has copilot && [[ -f "$TARGET/.github/copilot-instructions.md" ]]; then
        echo "    $step. Review $TARGET/.github/copilot-instructions.md (generated; commit alongside your rules)."
        step=$((step + 1))
    fi
    if agents_has gemini && [[ -f "$TARGET/GEMINI.md" ]]; then
        echo "    $step. Review $TARGET/GEMINI.md (generated; commit alongside your rules)."
        step=$((step + 1))
    fi
    if agents_has codex && [[ -f "$TARGET/AGENTS.md" ]]; then
        echo "    $step. Review $TARGET/AGENTS.md (generated; commit alongside your rules)."
        step=$((step + 1))
    fi
    echo "    $step. Review $TARGET/.gitignore for merge conflicts."
    step=$((step + 1))
    echo "    $step. Commit the new files."
fi
echo ""
echo "Tip: \`./install.sh --list\`  (with the same flags) — preview catalog as text."
echo "     \`./install.sh --list --json\`  — same catalog as JSON for automation."
echo "     \`./install.sh --dry-run ...\`  — show what would install without writing."
echo "     Opt into more with \`--features all\` or e.g. \`--features recommended,persistence,ai\`."

