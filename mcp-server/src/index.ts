#!/usr/bin/env node
/**
 * AppBootstrapAI MCP server entry point: builds the server (src/server.ts)
 * and serves it over stdio, the standard transport for local MCP servers.
 * Configure a client by pointing at the compiled `dist/index.js`.
 */

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createServer } from "./server.js";

// Load the category set from install.sh before accepting requests. If
// install.sh is missing or old, fail at startup instead of serving a stale or
// empty list (the install tools wouldn't work without it anyway).
let built: Awaited<ReturnType<typeof createServer>>;
try {
    built = await createServer();
} catch (e) {
    console.error(`appbootstrap-mcp: failed to load categories from install.sh: ${e instanceof Error ? e.message : String(e)}`);
    process.exit(1);
}

await built.server.connect(new StdioServerTransport());

// stderr is where MCP servers log; stdout is the transport.
console.error(`appbootstrap-mcp server connected via stdio (${built.categories.length} categories loaded)`);
