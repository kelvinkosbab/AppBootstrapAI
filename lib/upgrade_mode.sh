# shellcheck shell=bash
# AppBootstrapAI installer — --upgrade mode bash wrapper.
#
# Sourced from install.sh. Builds the BUNDLE_ALL + in_scope inputs that
# lib/upgrade.py needs (rules, skill files, settings, CLAUDE.md template,
# Cursor .mdc overlays, concat-agent overlays), then invokes the Python
# brain. After it returns, this block has exited the script (Python
# `sys.exit(0)`).

# --- --upgrade mode -----------------------------------------------------------
#
# Plan-only — reads the manifest, compares every tracked file against the
# bundle (3-way: installed hash vs. current disk vs. bundle), and prints what
# WOULD change. Writes nothing. Phase 3 will add --apply.

if [[ "$ACTION" == "upgrade" ]]; then
    if [[ ! -d "$TARGET" ]]; then
        echo "error: target directory does not exist: $TARGET" >&2
        exit 1
    fi
    TARGET="$(cd "$TARGET" && pwd)"
    manifest_path="$TARGET/.claude/.appbootstrap-manifest.json"

    if [[ ! -f "$manifest_path" ]]; then
        echo "error: no manifest at $manifest_path" >&2
        echo "       This target does not appear to be an AppBootstrapAI install." >&2
        echo "       Run install.sh first to create a manifest, then re-run --upgrade." >&2
        exit 1
    fi

    echo "==> Upgrade plan for $TARGET"
    if [[ "$UPGRADE_INHERITED_FROM_MANIFEST" == "true" ]]; then
        echo "    selection (inherited from manifest): --platform $PLATFORM --apple-language $APPLE_LANG --features $FEATURES_INPUT --agents $AGENTS_INPUT"
        echo "    (override any of these on the command line to opt into new categories or agents)"
    else
        echo "    selection: --platform $PLATFORM --apple-language $APPLE_LANG --features $FEATURES_INPUT --agents $AGENTS_INPUT"
    fi
    echo ""

    # ----- Build BUNDLE_ALL and BUNDLE_IN_SCOPE files for Python --------------
    #
    # BUNDLE_ALL: every shippable file in the bundle, with rel_path + type +
    # category + sha256 + skill_name. This is the "could be installed" universe.
    #
    # BUNDLE_IN_SCOPE: subset of BUNDLE_ALL that the current --platform /
    # --apple-language / --features combination would actually install. Computed
    # by reusing should_install_rule / should_install_skill above.
    #
    # Stored in temp files (pipe-separated) so the Python heredoc can mmap them
    # without us having to escape multi-line strings inline.
    bundle_all_tmp="$(mktemp)"
    bundle_in_scope_tmp="$(mktemp)"
    # Overlay dir for agent-derived files (Cursor .mdc, Copilot/Gemini/Codex concat).
    # Python uses it as a source-of-truth when the rel_path isn't in $SCRIPT_DIR.
    bundle_overlay_dir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$bundle_overlay_dir' '$bundle_all_tmp' '$bundle_in_scope_tmp'" EXIT

    # Rules. Always in BUNDLE_ALL; in_scope gated by agents_has claude.
    shopt -s nullglob
    for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
        name="$(basename "$f")"
        cat="$(file_category "$name")"; [[ -z "$cat" ]] && cat="-"
        hash="$(sha256_file "$f")"
        rel_path=".claude/rules/$name"
        echo "$rel_path|rule|$cat|$hash|" >> "$bundle_all_tmp"
        if agents_has claude && should_install_rule "$name"; then
            echo "$rel_path" >> "$bundle_in_scope_tmp"
        fi
    done

    # Skill files (one entry per file inside each skill dir).
    # Skills are Claude-only; gate in_scope on agents_has claude.
    for d in "$SCRIPT_DIR/.claude/skills/"*/; do
        skill_name="$(basename "$d")"
        cat="$(file_category "$skill_name")"; [[ -z "$cat" ]] && cat="-"
        skill_in_scope="false"
        if agents_has claude && should_install_skill "$skill_name"; then skill_in_scope="true"; fi
        while IFS= read -r -d '' src_file; do
            rel_path="${src_file#"$SCRIPT_DIR"/}"
            hash="$(sha256_file "$src_file")"
            echo "$rel_path|skill-file|$cat|$hash|$skill_name" >> "$bundle_all_tmp"
            if [[ "$skill_in_scope" == "true" ]]; then
                echo "$rel_path" >> "$bundle_in_scope_tmp"
            fi
        done < <(find "$d" -type f -print0)
    done

    # settings.json — Claude-only. In BUNDLE_ALL always so the manifest can
    # surface "you've stopped tracking this" diffs; in_scope only when claude
    # is selected.
    settings_hash="$(sha256_file "$SCRIPT_DIR/.claude/settings.json")"
    echo ".claude/settings.json|settings|-|$settings_hash|" >> "$bundle_all_tmp"
    if agents_has claude; then
        echo ".claude/settings.json" >> "$bundle_in_scope_tmp"
    fi

    # CLAUDE.md template — Claude-only too.
    case "$PLATFORM" in
        apple)   TEMPLATE_PATH="templates/CLAUDE.template.apple.md"   ;;
        android) TEMPLATE_PATH="templates/CLAUDE.template.android.md" ;;
        both)    TEMPLATE_PATH="templates/CLAUDE.template.md"         ;;
    esac
    template_hash="$(sha256_file "$SCRIPT_DIR/$TEMPLATE_PATH")"
    # The user's file on disk is CLAUDE.md; we tag the bundle-side path so the
    # plan can show "templates/CLAUDE.template.apple.md → CLAUDE.md".
    echo "CLAUDE.md|template|core|$template_hash|$TEMPLATE_PATH" >> "$bundle_all_tmp"
    if agents_has claude; then
        echo "CLAUDE.md" >> "$bundle_in_scope_tmp"
    fi

    # --- Agent-derived files (Phase 4) ---------------------------------------
    # For Cursor: each .claude/rules/<name>.md → .cursor/rules/<name>.mdc with
    # identical content (cp -p). For Copilot/Gemini/Codex: deterministic concat
    # of in-scope rules. Materialize all of these in the overlay dir so the
    # apply step has a real source path to copy from.

    if agents_has cursor; then
        mkdir -p "$bundle_overlay_dir/.cursor/rules"
        for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
            name="$(basename "$f")"
            cat="$(file_category "$name")"; [[ -z "$cat" ]] && cat="-"
            mdc_name="${name%.md}.mdc"
            cp "$f" "$bundle_overlay_dir/.cursor/rules/$mdc_name"
            hash="$(sha256_file "$bundle_overlay_dir/.cursor/rules/$mdc_name")"
            rel_path=".cursor/rules/$mdc_name"
            echo "$rel_path|agent-file-cursor|$cat|$hash|" >> "$bundle_all_tmp"
            if should_install_rule "$name"; then
                echo "$rel_path" >> "$bundle_in_scope_tmp"
            fi
        done
    fi

    # Helper for the three concat agents.
    _materialize_concat() {
        local rel_path="$1" tag="$2" banner="$3"
        local dst="$bundle_overlay_dir/$rel_path"
        mkdir -p "$(dirname "$dst")"
        concat_in_scope_rules "$banner" > "$dst"
        local hash; hash="$(sha256_file "$dst")"
        echo "$rel_path|$tag|-|$hash|" >> "$bundle_all_tmp"
        echo "$rel_path" >> "$bundle_in_scope_tmp"
    }
    if agents_has kiro; then
        mkdir -p "$bundle_overlay_dir/.kiro/steering"
        for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
            name="$(basename "$f")"
            cat="$(file_category "$name")"; [[ -z "$cat" ]] && cat="-"
            dst="$bundle_overlay_dir/.kiro/steering/$name"
            kiro_steering_from_rule "$f" > "$dst"
            hash="$(sha256_file "$dst")"
            rel_path=".kiro/steering/$name"
            echo "$rel_path|agent-file-kiro|$cat|$hash|" >> "$bundle_all_tmp"
            if should_install_rule "$name"; then
                echo "$rel_path" >> "$bundle_in_scope_tmp"
            fi
        done
    fi

    if agents_has copilot; then
        _materialize_concat ".github/copilot-instructions.md" "agent-file-copilot" "GitHub Copilot"
    fi
    if agents_has gemini; then
        _materialize_concat "GEMINI.md" "agent-file-gemini" "Gemini CLI"
    fi
    if agents_has codex; then
        _materialize_concat "AGENTS.md" "agent-file-codex" "Codex CLI and other AGENTS.md-aware tools"
    fi

    # RENAMES.md path (may not exist; Python tolerates missing file).
    renames_path="$SCRIPT_DIR/RENAMES.md"
    # MCP paths — settings.local.json on the target, recipes dir in the bundle.
    settings_local_path="$TARGET/.claude/settings.local.json"

    # Plan computation + apply executor. See lib/upgrade.py.
    python3 "$SCRIPT_DIR/lib/upgrade.py" \
        "$manifest_path" "$TARGET" "$bundle_all_tmp" "$bundle_in_scope_tmp" "$renames_path" \
        "$PLATFORM" "$APPLE_LANG" "$FEATURES_INPUT" "$SCRIPT_DIR" \
        "$APPLY" "$FORCE_CONFLICTS" "$PRUNE" "$MIGRATE_MANIFEST" "$DRY_RUN" "$BUNDLE_COMMIT" \
        "$settings_local_path" "$MCP_RECIPES_DIR" "$bundle_overlay_dir" \
        "$AGENTS_INPUT" "$SELECTED_AGENTS" "$BUNDLE_GH_REMOTE"

    exit 0
fi

