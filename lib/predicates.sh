# shellcheck shell=bash
# AppBootstrapAI installer — predicates + helpers.
#
# Sourced from install.sh. All functions here are PURE — they read from
# globals (SELECTED_FEATURES, PLATFORM, APPLE_LANG, SELECTED_AGENTS, etc.)
# but don't modify state. Safe to call repeatedly from any mode.
#
# Functions defined:
#   file_category(name)            → category string ("core", "ui", ...) or "" or "objc-gated"
#   is_in_features(name)           → exit 0 if the file's category is in SELECTED_FEATURES
#   should_install_rule(name)      → exit 0 if the rule file is in scope (platform+lang+features)
#   should_install_skill(name)     → exit 0 if the skill dir is in scope
#   should_install_any_skills()    → exit 0 if ANY skill would install under current selection
#   rule_description(path)         → emit the `description:` line from a rule's YAML frontmatter
#   skill_description(dir)         → emit the description from SKILL.md
#   json_escape                    → filter stdin: escape \, ", tab; strip newlines
#   sha256_file(path)              → hex digest of the file's contents (portable; shasum or sha256sum)
#   concat_in_scope_rules(label)   → deterministic concat of every in-scope rule + a banner
#   json_string_array(items)       → print a JSON string-array from a space-separated list

# Map a rule/skill basename to its category. Returns empty string if uncategorized
# (uncategorized files install unconditionally — used for things not yet
# slotted into a category, though there shouldn't be any in practice).
# Returns "objc-gated" for apple-objc-best-practices.md — it's filtered by
# --apple-language, not --features.
file_category() {
    case "$1" in
        project-documentation.md|concise-comments-and-commits.md)
            echo "core" ;;
        apple-swift6-strict-concurrency.md|swift-concurrency-pro|android-coroutines-best-practices.md|android-coroutines-pro)
            echo "concurrency" ;;
        apple-swiftui-mvvm.md|apple-accessibility-best-practices.md|apple-objc-accessibility-best-practices.md|swiftui-pro|swift-accessibility-pro|android-compose-best-practices.md|android-accessibility-best-practices.md|android-compose-pro|android-accessibility-pro|android-large-screen-best-practices.md|android-adaptive-layout-pro)
            echo "ui" ;;
        apple-testing-strategy.md|swift-testing-pro|android-testing-strategy.md)
            echo "testing" ;;
        apple-documentation-strategy.md|swift-docc-pro|android-documentation-strategy.md)
            echo "docs" ;;
        swift-error-handling-pro)
            echo "error-handling" ;;
        apple-spm-package-conventions.md|apple-modular-architecture.md|swift-package-pro|android-gradle-conventions.md|android-project-rules.md|android-gradle-architecture-pro)
            echo "packaging" ;;
        swift-logging-pro|apple-logging-strategy.md|android-logging-strategy.md)
            echo "logging" ;;
        apple-localization-best-practices.md|android-localization-best-practices.md)
            echo "localization" ;;
        apple-linting-strategy.md|android-linting-strategy.md)
            echo "linting" ;;
        coredata-swift6-pro|swiftdata-pro)
            echo "persistence" ;;
        apple-foundation-models.md|android-ai-best-practices.md)
            echo "ai" ;;
        xml-to-compose-migration-pro)
            echo "migration" ;;
        r8-shrink-pro)
            echo "shrinking" ;;
        apple-visionos-best-practices.md)
            echo "spatial" ;;
        apple-testflight-deployment.md|android-play-beta-deployment.md)
            echo "deployment" ;;
        apple-objc-best-practices.md)
            echo "objc-gated" ;;
        *)
            echo "" ;;
    esac
}

# Check whether a file's category is enabled under --features.
is_in_features() {
    local cat feature
    cat="$(file_category "$1")"
    # objc-gated and uncategorized files bypass the --features filter.
    [[ "$cat" == "objc-gated" || -z "$cat" ]] && return 0
    for feature in $SELECTED_FEATURES; do
        if [[ "$feature" == "$cat" ]]; then return 0; fi
    done
    return 1
}

# Whether an Android form-factor token (phone/tablet/wear/tv/auto) is in the
# resolved --android-platforms set. The first consumer is the large-screen /
# foldable rule + skill, gated by `tablet`.
android_platform_selected() {
    local p
    for p in $SELECTED_ANDROID_PLATFORMS; do
        [[ "$p" == "$1" ]] && return 0
    done
    return 1
}

# --- Inclusion predicates -----------------------------------------------------
# Decide whether a given rule file should be installed for the current
# (PLATFORM, APPLE_LANG, FEATURES) combination.

should_install_rule() {
    local name="$1"
    case "$name" in
        apple-objc-best-practices.md)
            # The core "modern ObjC" rule — gated *only* by --apple-language,
            # not --features. If you opted into ObjC at all, you want this.
            [[ "$PLATFORM" != "android" ]] && [[ "$APPLE_LANG" != "swift" ]]
            ;;
        apple-objc-*)
            # Other ObjC-specific rules (e.g., apple-objc-accessibility-best-practices.md)
            # are categorized — gated by BOTH --apple-language AND --features.
            [[ "$PLATFORM" != "android" ]] && [[ "$APPLE_LANG" != "swift" ]] && is_in_features "$name"
            ;;
        apple-*)
            # Other apple-* rules are Swift-side: include if Apple in scope and
            # language is swift or both AND the rule's category is selected.
            [[ "$PLATFORM" != "android" ]] && [[ "$APPLE_LANG" != "objc" ]] && is_in_features "$name"
            ;;
        android-large-screen-*)
            # Form-factor rule: gated by --features (ui) AND the `tablet` token
            # in --android-platforms (the default includes it).
            [[ "$PLATFORM" != "apple" ]] && is_in_features "$name" && android_platform_selected tablet
            ;;
        android-*)
            [[ "$PLATFORM" != "apple" ]] && is_in_features "$name"
            ;;
        *)
            # Unprefixed rules (like project-documentation.md) — gated by --features only.
            is_in_features "$name"
            ;;
    esac
}

# Per-skill inclusion.
should_install_skill() {
    local name="$1"
    case "$name" in
        android-adaptive-layout-pro)
            # Form-factor skill — also needs `tablet` in --android-platforms.
            [[ "$PLATFORM" != "apple" ]] && is_in_features "$name" && android_platform_selected tablet
            ;;
        android-*|xml-to-compose-*|r8-shrink-*)
            # Android skill — install when Android is in scope AND feature selected.
            [[ "$PLATFORM" != "apple" ]] && is_in_features "$name"
            ;;
        *)
            # Apple/Swift skill — install when Apple+Swift is in scope AND feature selected.
            [[ "$PLATFORM" != "android" ]] && [[ "$APPLE_LANG" != "objc" ]] && is_in_features "$name"
            ;;
    esac
}

# Whether ANY skills will install — drives the "Copying skills" log message.
should_install_any_skills() {
    local skill_dir
    shopt -s nullglob
    for skill_dir in "$SCRIPT_DIR/.claude/skills/"*/; do
        if should_install_skill "$(basename "$skill_dir")"; then
            return 0
        fi
    done
    return 1
}

# Pull the `description:` line out of a rule's YAML frontmatter (best-effort).
rule_description() {
    awk '
        /^---$/ { if (seen) exit; seen=1; next }
        /^description:/ { sub(/^description:[[:space:]]*/, ""); print; exit }
    ' "$1"
}

skill_description() {
    rule_description "$1/SKILL.md"
}

# JSON-escape a string from stdin. Handles backslash, double-quote, tab.
# Strips newlines (descriptions should be single-line; if they aren't, this
# prevents invalid JSON).
json_escape() {
    tr -d '\n' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g'
}

# Portable SHA-256 of a file. macOS ships `shasum`; many Linux images ship
# `sha256sum`. Returns just the hex digest with no trailing filename.
# Returns empty string if the file is missing (caller can record null).
sha256_file() {
    local path="$1"
    [[ -f "$path" ]] || { echo ""; return; }
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$path" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$path" | awk '{print $1}'
    else
        echo "error: need shasum or sha256sum on PATH for manifest hashing" >&2
        exit 1
    fi
}

# Emit a deterministic concatenation of every in-scope rule. Used for the
# single-file non-Claude agents (Copilot, Gemini, Codex). Output is identical
# given the same SCRIPT_DIR contents + --platform / --apple-language / --features,
# so hashing the output gives a stable bundle hash across install/upgrade.
#
# The first line of the output is a generated-banner identifying the source
# and disclaiming hand-edits. Each rule is delimited by an HR + the basename
# as a heading, so a human reading the concat can navigate.
#
# Usage: concat_in_scope_rules <banner_purpose>   →  prints to stdout
#   banner_purpose is a short label like "GitHub Copilot" / "Gemini CLI" /
#   "Codex (AGENTS.md)" that gets baked into the header so the generated
#   file's first line tells you what tool it's for.
concat_in_scope_rules() {
    local banner_purpose="$1"
    echo "<!-- Generated by AppBootstrapAI install.sh for ${banner_purpose}. -->"
    echo "<!-- Do not edit this file directly. Edit .claude/rules/ in the bundle and re-run install.sh / --upgrade --apply. -->"
    echo "<!-- Source of truth: https://github.com/kelvinkosbab/AppBootstrapAI -->"
    echo ""
    # Iterate alphabetically — that's what shell glob already does, but be explicit so
    # the contract "deterministic output" doesn't depend on filesystem ordering.
    shopt -s nullglob
    local f name
    for f in $(printf '%s\n' "$SCRIPT_DIR/.claude/rules/"*.md | LC_ALL=C sort); do
        name="$(basename "$f")"
        if should_install_rule "$name"; then
            echo "## $name"
            echo ""
            cat "$f"
            echo ""
            echo ""
            echo "---"
            echo ""
        fi
    done
}

# Split a comma-separated glob list on TOP-LEVEL commas only — commas inside
# `{...}` brace groups are kept (so `**/*.{kt,kts}` stays one pattern, while
# `Package.swift,**/Package.swift` splits into two). One pattern per line.
_split_top_level_commas() {
    awk -v s="$1" 'BEGIN{
        depth=0; cur="";
        for (i=1; i<=length(s); i++) {
            c = substr(s, i, 1);
            if (c == "{") { depth++; cur = cur c; continue }
            if (c == "}") { if (depth>0) depth--; cur = cur c; continue }
            if (c == "," && depth == 0) { if (cur != "") print cur; cur = ""; continue }
            cur = cur c;
        }
        if (cur != "") print cur;
    }'
}

# Transform a .claude/rules/<name>.md into a Kiro steering file (Amazon Kiro,
# https://kiro.dev/docs/steering/). Kiro steering lives in .kiro/steering/*.md
# with YAML frontmatter using `inclusion` + `fileMatchPattern` (glob), NOT our
# `description`/`globs` keys — so we rewrite the frontmatter and keep the body.
# Each rule's `globs` maps directly to `fileMatchPattern` (single quoted string,
# or an inline YAML array when the rule lists several top-level patterns), so a
# rule only enters Kiro's context when a matching file is open — preserving the
# same glob-scoping (and token economy) the Claude rules have.
#
# Output is deterministic for a given rule file, so install + the upgrade overlay
# produce byte-identical content and the 3-way hash diff works.
#
# Usage: kiro_steering_from_rule <rule_md_path>   →  prints to stdout
kiro_steering_from_rule() {
    local rule_file="$1"
    local globs
    globs="$(awk -F': ' '/^globs:/{print $2; exit}' "$rule_file")"
    # Strip a single layer of surrounding double quotes.
    globs="${globs%\"}"; globs="${globs#\"}"

    local patterns=() p
    while IFS= read -r p; do [[ -n "$p" ]] && patterns+=("$p"); done \
        < <(_split_top_level_commas "$globs")

    printf -- '---\n'
    printf -- 'inclusion: fileMatch\n'
    if [[ "${#patterns[@]}" -le 1 ]]; then
        printf -- "fileMatchPattern: '%s'\n" "${patterns[0]:-**/*}"
    else
        local joined="" first=1
        for p in "${patterns[@]}"; do
            if [[ "$first" -eq 1 ]]; then first=0; else joined="$joined, "; fi
            joined="$joined'$p'"
        done
        printf -- 'fileMatchPattern: [%s]\n' "$joined"
    fi
    printf -- '---\n\n'

    # Emit the rule body verbatim — everything after the rule's own frontmatter.
    # Once past the two `---` delimiters, print every line (including any literal
    # `---` horizontal rules / YAML examples inside the body).
    awk 'fm>=2 {print; next} /^---[[:space:]]*$/ {fm++}' "$rule_file"
}

# Print a JSON-array of strings from a space-separated list.
json_string_array() {
    local items="$1"
    local first=1 item
    printf '['
    for item in $items; do
        if [[ "$first" -eq 1 ]]; then first=0; else printf ', '; fi
        printf '"%s"' "$item"
    done
    printf ']'
}
