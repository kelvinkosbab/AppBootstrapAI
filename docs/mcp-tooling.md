# Companion MCP tooling

Optional MCP servers that pair well with the bundle. `./install.sh --list-mcps` lists the recipes `--with-mcps` can wire in.

#### MCP servers for the Apple side

- **Xcode 27 native MCP + agent platform** *(WWDC 2026)* — Apple massively expanded the in-Xcode agent story (building on the Xcode 26.3 `mcpbridge` foundation). The native **Xcode MCP server** now adds debug tools (run state, debugger console, schemes, destinations, build settings, entitlements, `Info.plist`), a **Preview Snapshot** tool, simulator control (boot/install/launch, synthesize touches, screenshots), and access to project insights (crashes, hangs, energy). **LLDB ships its own `lldb-mcp`** server ([docs](https://lldb.llvm.org/use/mcp.html)). Most relevant to *this* bundle: Xcode 27 gains **agent plug-ins** — bundling **skills, MCP servers, ACP (Agent Client Protocol) configurations, and slash commands** — plus Apple-built specialists (localization, accessibility, UIKit resizing) and a security layer governing agent filesystem access. First-party, no separate install. See Apple's [Giving agentic coding tools access to Xcode](https://developer.apple.com/documentation/xcode/giving-agentic-coding-tools-access-to-xcode).
- **[XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP)** — community MCP server that lets any agent drive Xcode: build schemes, run simulators, capture logs. Still useful alongside the native server — it leans into richer test/simulator tooling and works from agents outside Xcode. Especially valuable for legacy / mixed-language Apple codebases and for CI-style automation.

#### MCP servers for the Android side

- **[Android Studio's built-in MCP support](https://developer.android.com/studio/gemini/add-mcp-server)** — Google ships first-party MCP integration in Android Studio. Hook any MCP server (including this repo's, see below) directly into Studio's agent.
- **[`android-mcp-server`](https://github.com/minhalvp/android-mcp-server)** — community MCP server that gives agents control over Android devices and emulators via ADB. The Android-side parallel to XcodeBuildMCP's simulator work.

#### Cross-platform / shared

- **[Firebase MCP](https://github.com/firebase/firebase-tools/tree/main/src/mcp)** — **first-party from Google.** Lives in `firebase-tools`. Covers Crashlytics, Remote Config, App Hosting, Realtime DB, and Cloud Functions logs. Crashlytics surface is marked experimental.
- **[Sentry MCP](https://docs.sentry.io/product/sentry-mcp/)** — **first-party, hosted by Sentry** at `mcp.sentry.dev/mcp`. Streamable HTTP with OAuth — zero install for sentry.io users. Exposes issues, errors, projects, and Seer analysis.

**See also** (specialized; add when the use case fits):

- **[`ios-simulator-mcp`](https://github.com/joshuayoes/ios-simulator-mcp)** — npm-installable, iOS-Simulator-only (screenshots, UI hierarchy, tap/swipe). Lighter than XcodeBuildMCP if Simulator control is all you need.
- **[Mobile MCP (`mobile-next/mobile-mcp`)](https://mcpservers.org/servers/mobile-next/mobile-mcp)** — cross-platform iOS + Android automation via accessibility snapshots + coordinate taps. QA-style workflows that span both platforms.
- **[`kotlin-mcp-server`](https://github.com/normaltusker/kotlin-mcp-server)** — heavier-touch Android dev workflow MCP: Gradle, ktlint, Lint, Room / Retrofit / Compose scaffolding via AI prompts.
- **[Figma MCP](https://help.figma.com/hc/en-us/articles/32132100833559-Guide-to-the-Figma-MCP-server)** — first-party Figma server for design → code workflow. Mobile-relevant when your design source is Figma; not mobile-specific.
- **App Store Connect** and **Google Play Console** MCPs exist but the ecosystem is still consolidating around a winner — multiple competing community implementations. Worth watching but no recommendation yet.
- **Linear / Jira / Atlassian** MCPs (Atlassian's is GA Feb 2026, Linear's is first-party) are excellent but cover generic project-management concerns, not mobile-app-specific work — they belong in your generic MCP setup, not this list.

#### Cross-tool rule sync

- **Multi-agent support** — pass `--agents copilot,cursor,gemini,codex,kiro` to `install.sh` and the bundle writes the right file shape for each agent (in addition to or instead of Claude). For agents not in that built-in set (Cline, Goose, Roo, Windsurf, etc.), point a sync tool at `.claude/`. See [Using with non-Claude AI agents](agents.md).
