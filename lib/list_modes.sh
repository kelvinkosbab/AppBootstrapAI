# shellcheck shell=bash
# AppBootstrapAI installer — read-only catalog handlers.
#
# Sourced from install.sh. Both modes exit 0 after printing (they never fall
# through to install/upgrade/uninstall). Dispatched-to via ACTION:
#   ACTION=list-mcps → prints curated MCP recipes from $MCP_RECIPES_DIR
#   ACTION=list      → prints the rules + skills catalog under current selection,
#                      optionally as JSON when --json was passed

# --- --list-mcps mode ---------------------------------------------------------

if [[ "$ACTION" == "list-mcps" ]]; then
    echo "AppBootstrapAI MCP recipes"
    echo "  Add one or more to your repo with: --with-mcps <name1>,<name2>"
    echo "  Each recipe writes one entry under .claude/settings.local.json's"
    echo "  \"mcpServers\" key. Existing entries are never overwritten."
    echo ""
    if [[ ! -d "$MCP_RECIPES_DIR" ]]; then
        echo "  (no recipes directory at $MCP_RECIPES_DIR)"
        exit 0
    fi
    shopt -s nullglob
    for recipe in "$MCP_RECIPES_DIR"/*.json; do
        python3 - "$recipe" <<'PYTHON'
import json, sys, textwrap
with open(sys.argv[1]) as f:
    r = json.load(f)
plat = r.get("platform", "-")
name = r.get("name", "?")
display = r.get("display_name", name)
desc = r.get("description", "")
homepage = r.get("homepage", "")
print(f"  [{plat:14s}] {name}")
print(f"      {display}")
for line in textwrap.wrap(desc, width=76, initial_indent="      ", subsequent_indent="      "):
    print(line)
if homepage:
    print(f"      {homepage}")
print()
PYTHON
    done
    exit 0
fi

# --- --list mode --------------------------------------------------------------

if [[ "$ACTION" == "list" ]]; then
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        # Machine-readable catalog. Stable schema for automation / MCP consumers.
        printf '{\n'
        printf '  "selection": {\n'
        printf '    "platform": "%s",\n' "$PLATFORM"
        printf '    "apple_language": "%s",\n' "$APPLE_LANG"
        printf '    "features_input": "%s",\n' "$FEATURES_INPUT"
        printf '    "features_resolved": '
        json_string_array "$SELECTED_FEATURES"
        printf ',\n'
        printf '    "agents_input": "%s",\n' "$AGENTS_INPUT"
        printf '    "agents_resolved": '
        json_string_array "$SELECTED_AGENTS"
        printf '\n  },\n'

        # Canonical category catalog — single source of truth for consumers
        # (e.g. the MCP server) that need the full set + which are in the
        # `recommended` preset. Driven by ALL_CATEGORIES / RECOMMENDED_CATEGORIES.
        printf '  "categories": [\n'
        first_cat=1
        for cat_name in $ALL_CATEGORIES; do
            recommended="false"
            case " $RECOMMENDED_CATEGORIES " in
                *" $cat_name "*) recommended="true" ;;
            esac
            if [[ "$first_cat" -eq 1 ]]; then first_cat=0; else printf ',\n'; fi
            printf '    {"name": "%s", "recommended": %s}' "$cat_name" "$recommended"
        done
        printf '\n  ],\n'

        printf '  "rules": [\n'
        shopt -s nullglob
        first_rule=1
        for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
            name="$(basename "$f")"
            cat="$(file_category "$name")"
            [[ -z "$cat" ]] && cat="-"
            if should_install_rule "$name"; then installed="true"; else installed="false"; fi
            desc="$(rule_description "$f" | json_escape)"
            if [[ "$first_rule" -eq 1 ]]; then first_rule=0; else printf ',\n'; fi
            printf '    {"filename": "%s", "category": "%s", "installed": %s, "description": "%s"}' \
                "$name" "$cat" "$installed" "$desc"
        done
        printf '\n  ],\n'

        printf '  "skills": [\n'
        first_skill=1
        for d in "$SCRIPT_DIR/.claude/skills/"*/; do
            name="$(basename "$d")"
            cat="$(file_category "$name")"
            [[ -z "$cat" ]] && cat="-"
            if should_install_skill "$name"; then installed="true"; else installed="false"; fi
            desc="$(skill_description "$d" | json_escape)"
            if [[ "$first_skill" -eq 1 ]]; then first_skill=0; else printf ',\n'; fi
            printf '    {"name": "%s", "category": "%s", "installed": %s, "description": "%s"}' \
                "$name" "$cat" "$installed" "$desc"
        done
        printf '\n  ]\n'
        printf '}\n'
        exit 0
    fi

    # Human-readable catalog.
    echo "AppBootstrapAI catalog"
    echo "  current selection: --platform $PLATFORM --apple-language $APPLE_LANG --features $FEATURES_INPUT"
    echo "  resolved features: $SELECTED_FEATURES"
    echo ""
    echo "Rules:"
    shopt -s nullglob
    for f in "$SCRIPT_DIR/.claude/rules/"*.md; do
        name="$(basename "$f")"
        if should_install_rule "$name"; then mark="✓"; else mark=" "; fi
        cat="$(file_category "$name")"
        [[ -z "$cat" ]] && cat="-"
        printf "  [%s] %-50s  (%s)\n        %s\n" "$mark" "$name" "$cat" "$(rule_description "$f")"
    done
    echo ""
    echo "Skills:"
    for d in "$SCRIPT_DIR/.claude/skills/"*/; do
        name="$(basename "$d")"
        if should_install_skill "$name"; then mark="✓"; else mark=" "; fi
        cat="$(file_category "$name")"
        [[ -z "$cat" ]] && cat="-"
        printf "  [%s] %-40s  (%s)\n        %s\n" "$mark" "$name" "$cat" "$(skill_description "$d")"
    done
    echo ""
    echo "Legend: [✓] = installed under current selection, [ ] = skipped."
    echo "        Category in parentheses is what --features gates the file by."
    echo "        Pass --json for machine-readable output."
    exit 0
fi

