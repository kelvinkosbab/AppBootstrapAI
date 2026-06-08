# shellcheck shell=bash
# shellcheck disable=SC2034  # this file's job is to set globals read by install.sh
# AppBootstrapAI installer — interactive guided flow (-i / --interactive).
#
# Sourced from install.sh and invoked via run_interactive() right after arg
# parsing, before feature/agent resolution and platform autodetect — so the
# answers it gathers feed the normal pipeline exactly as if they'd been passed
# as flags.
#
# Reads answers with `read` (works at a TTY and from piped stdin). Every prompt
# shows a default; pressing Enter (or EOF on piped input) accepts it. The flow
# detects whether you're creating / adopting / updating and sets the globals:
#   TARGET, ACTION, PLATFORM, APPLE_LANG, FEATURES_INPUT, AGENTS_INPUT,
#   WITH_MCPS, NEW_PROJECT, APPLY  (plus the *_EXPLICIT flags upgrade-inherit reads)
#
# It never writes files itself — it just populates the selection and hands back
# to install.sh's normal dispatch.

# ask <var> <prompt> <default>  → reads a line into <var>, falling back to default.
_iask() {
    local __var="$1" __prompt="$2" __default="$3" __reply
    # shellcheck disable=SC2229
    read -r -p "$__prompt [$__default]: " __reply || __reply=""
    [[ -z "$__reply" ]] && __reply="$__default"
    printf -v "$__var" '%s' "$__reply"
}

# yesno <prompt> <default y|n>  → returns 0 for yes, 1 for no.
_iyesno() {
    local __prompt="$1" __default="$2" __reply __hint
    [[ "$__default" == "y" ]] && __hint="Y/n" || __hint="y/N"
    read -r -p "$__prompt [$__hint]: " __reply || __reply=""
    [[ -z "$__reply" ]] && __reply="$__default"
    case "$__reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

run_interactive() {
    echo "==> AppBootstrapAI — guided setup"
    echo "    (press Enter to accept each [default]; Ctrl-C to bail)"
    echo ""

    # --- 1. Target directory --------------------------------------------------
    _iask TARGET "Target directory" "${TARGET:-.}"

    # --- 2. Detect situation: create / adopt / update -------------------------
    local manifest="$TARGET/.claude/.appbootstrap-manifest.json"
    if [[ ! -d "$TARGET" ]]; then
        echo ""
        echo "    '$TARGET' doesn't exist yet → NEW PROJECT."
        if _iyesno "    Create it (and git init)?" "y"; then
            NEW_PROJECT="true"
            ACTION="install"
        else
            echo "    Nothing to do without a target. Exiting."
            exit 0
        fi
    elif [[ -f "$manifest" ]]; then
        echo ""
        echo "    '$TARGET' already has an AppBootstrapAI install → UPDATE."
        if _iyesno "    Review available updates (--upgrade)?" "y"; then
            ACTION="upgrade"
            # Selection inherits from the manifest unless changed below; for a
            # plain update we keep it and just run the plan, then offer --apply.
            if _iyesno "    Apply the plan now (write changes)?" "n"; then
                APPLY="true"
            fi
            echo ""
            echo "==> Running upgrade ($([[ "$APPLY" == "true" ]] && echo "apply" || echo "plan only"))…"
            return 0     # upgrade inherits selection from the manifest; skip the rest
        else
            echo "    Exiting — use --force to re-install, or --uninstall to remove."
            exit 0
        fi
    else
        echo ""
        echo "    '$TARGET' exists with no AppBootstrapAI install → ADOPT into existing project."
        ACTION="install"
    fi

    # --- 3. Platform ----------------------------------------------------------
    # Offer autodetect as the default for an existing dir; for a brand-new dir
    # there's nothing to detect, so default to a sensible 'both'. This is a
    # local mini-detector (the shared detect_platform() in lib/detect_platform.sh
    # is sourced later in install.sh; interactive runs before that to let an
    # 'update' choice feed the manifest-inheritance step).
    local plat_default="both"
    if [[ -d "$TARGET" ]]; then
        local _has_apple="" _has_android=""
        [[ -f "$TARGET/Package.swift" ]] && _has_apple=1
        compgen -G "$TARGET/*.xcodeproj"   >/dev/null 2>&1 && _has_apple=1
        compgen -G "$TARGET/*.xcworkspace" >/dev/null 2>&1 && _has_apple=1
        if [[ -f "$TARGET/build.gradle" || -f "$TARGET/build.gradle.kts" \
           || -f "$TARGET/settings.gradle" || -f "$TARGET/settings.gradle.kts" \
           || -f "$TARGET/gradlew" ]]; then _has_android=1; fi
        if   [[ -n "$_has_apple" && -n "$_has_android" ]]; then plat_default="both"
        elif [[ -n "$_has_apple"   ]]; then plat_default="apple"
        elif [[ -n "$_has_android" ]]; then plat_default="android"
        fi
    fi
    echo ""
    local plat
    _iask plat "Platform (apple / android / both)" "$plat_default"
    PLATFORM="$plat"

    # --- 4. Apple language (only if apple in scope) ---------------------------
    if [[ "$PLATFORM" != "android" ]]; then
        local lang
        _iask lang "Apple language (swift / objc / both)" "swift"
        if [[ "$lang" != "swift" ]]; then APPLE_LANG="$lang"; APPLE_LANG_EXPLICIT="true"; fi
    fi

    # --- 5. Features ----------------------------------------------------------
    echo ""
    echo "    Feature presets: 'recommended' (most apps) | 'all' (everything) | custom CSV"
    echo "    Opt-in extras beyond recommended: persistence, ai, migration, shrinking, spatial, deployment"
    local feats
    _iask feats "Features" "recommended"
    if [[ "$feats" != "recommended" ]]; then FEATURES_INPUT="$feats"; FEATURES_EXPLICIT="true"; fi

    # --- 6. Agents ------------------------------------------------------------
    echo ""
    echo "    Agents: claude (default) | copilot | cursor | gemini | codex | all (additive CSV)"
    local agents
    _iask agents "Agents" "claude"
    if [[ "$agents" != "claude" ]]; then AGENTS_INPUT="$agents"; AGENTS_EXPLICIT="true"; fi

    # --- 7. MCP recipes (optional) --------------------------------------------
    echo ""
    if _iyesno "    Add MCP server recipes? (XcodeBuildMCP, Firebase, Sentry, …)" "n"; then
        local _avail="" _rf
        shopt -s nullglob
        for _rf in "$MCP_RECIPES_DIR"/*.json; do
            _rf="$(basename "$_rf" .json)"
            _avail="${_avail:+$_avail, }$_rf"
        done
        echo "    Available: $_avail"
        local mcps
        _iask mcps "MCP recipes (CSV, blank for none)" ""
        [[ -n "$mcps" ]] && WITH_MCPS="$mcps"
    fi

    # --- 8. Summary + confirm -------------------------------------------------
    echo ""
    echo "==> Plan:"
    echo "    action:    $([[ "$NEW_PROJECT" == "true" ]] && echo "create new project" || echo "adopt into existing project")"
    echo "    target:    $TARGET"
    echo "    platform:  $PLATFORM   apple-language: $APPLE_LANG"
    echo "    features:  $FEATURES_INPUT"
    echo "    agents:    $AGENTS_INPUT"
    [[ -n "$WITH_MCPS" ]] && echo "    mcps:      $WITH_MCPS"
    echo ""
    if ! _iyesno "    Proceed?" "y"; then
        echo "    Cancelled. Nothing written."
        exit 0
    fi
    echo ""
}
