import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { SSEClientTransport } from "@modelcontextprotocol/sdk/client/sse.js";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import {
  CallToolRequestSchema,
  CallToolResult,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

interface BuddySession {
  id: string;
  host: string;
  port: number;
  cwd: string;
  label?: string | null;
  pid?: number;
  started_at?: number | string;
  last_seen?: number;
}

type SessionsRegistryV1 = {
  version?: number;
  sessions: Record<string, Omit<BuddySession, "id">>;
};

type SessionsRegistryLegacyArray = {
  sessions: BuddySession[];
};

// ─────────────────────────────────────────────────────────────────────────────
// Logging (stderr only)
// ─────────────────────────────────────────────────────────────────────────────

function log(level: "info" | "warn" | "error", msg: string, data?: unknown) {
  const timestamp = new Date().toISOString();
  const line = `[${timestamp}] [${level.toUpperCase()}] ${msg}`;
  if (data !== undefined) {
    console.error(line, data);
  } else {
    console.error(line);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sessions Registry
// ─────────────────────────────────────────────────────────────────────────────

function getSessionsPath(): string {
  const xdgState = process.env.XDG_STATE_HOME;
  if (xdgState) {
    return path.join(xdgState, "nvim", "buddy", "sessions.json");
  }
  return path.join(os.homedir(), ".local", "state", "nvim", "buddy", "sessions.json");
}

function normalizeSessions(raw: unknown): BuddySession[] {
  if (!raw || typeof raw !== "object") return [];

  // Legacy helper format: { sessions: BuddySession[] }
  const maybeArray = raw as SessionsRegistryLegacyArray;
  if (Array.isArray(maybeArray.sessions)) {
    return maybeArray.sessions
      .filter((s): s is BuddySession => !!s && typeof (s as any).id === "string")
      .map((s) => ({
        ...s,
        host: s.host || "127.0.0.1",
      }));
  }

  // buddy.nvim format: { version: 1, sessions: { [id]: { host, port, cwd, ... } } }
  const maybeV1 = raw as SessionsRegistryV1;
  if (maybeV1.sessions && typeof maybeV1.sessions === "object") {
    return Object.entries(maybeV1.sessions).flatMap(([id, s]) => {
        const host = (s as any).host || "127.0.0.1";
        const port = Number((s as any).port);
        const cwd = String((s as any).cwd || "");
        if (!id || !Number.isFinite(port) || !cwd) return [];
        return [
          {
          id,
          host,
          port,
          cwd,
          label: (s as any).label ?? null,
          pid: typeof (s as any).pid === "number" ? (s as any).pid : undefined,
          started_at: (s as any).started_at,
          last_seen: typeof (s as any).last_seen === "number" ? (s as any).last_seen : undefined,
          } satisfies BuddySession,
        ];
      });
  }

  return [];
}

function loadSessions(): BuddySession[] {
  const sessionsPath = getSessionsPath();
  try {
    if (!fs.existsSync(sessionsPath)) {
      log("info", `Sessions file not found: ${sessionsPath}`);
      return [];
    }
    const content = fs.readFileSync(sessionsPath, "utf-8");
    const raw = JSON.parse(content);
    return normalizeSessions(raw);
  } catch (err) {
    log("error", `Failed to load sessions from ${sessionsPath}`, err);
    return [];
  }
}

function fuzzyIncludes(haystack: string, needle: string): boolean {
  return haystack.toLowerCase().includes(needle.toLowerCase());
}

function resolveSession(
  sessions: BuddySession[],
  selector: { id?: string; label?: string; cwd?: string; index?: number }
): BuddySession | null {
  if (selector.id) {
    return sessions.find((s) => s.id === selector.id) ?? null;
  }

  if (typeof selector.index === "number") {
    const sorted = [...sessions].sort((a, b) => {
      const aSeen = a.last_seen ?? 0;
      const bSeen = b.last_seen ?? 0;
      return bSeen - aSeen;
    });
    const idx = selector.index - 1;
    return sorted[idx] ?? null;
  }

  if (selector.label) {
    const matches = sessions.filter((s) =>
      s.label ? fuzzyIncludes(String(s.label), selector.label!) : false
    );
    if (matches.length === 1) return matches[0];
    if (matches.length > 1) {
      matches.sort((a, b) => (b.last_seen ?? 0) - (a.last_seen ?? 0));
      return matches[0];
    }
  }

  if (selector.cwd) {
    const matches = sessions.filter((s) => fuzzyIncludes(s.cwd, selector.cwd!));
    if (matches.length === 1) return matches[0];
    if (matches.length > 1) {
      matches.sort((a, b) => (b.last_seen ?? 0) - (a.last_seen ?? 0));
      return matches[0];
    }
  }

  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Meta Tools Definition
// ─────────────────────────────────────────────────────────────────────────────

const META_TOOLS: Tool[] = [
  {
    name: "buddy_sessions_list",
    description:
      "List all available buddy.nvim sessions from the sessions registry",
    inputSchema: {
      type: "object" as const,
      properties: {},
      required: [],
    },
  },
  {
    name: "buddy_session_select",
    description:
      "Select a buddy.nvim session by ID to connect to. This will expose that session's tools.",
    inputSchema: {
      type: "object" as const,
      properties: {
        session_id: {
          type: "string",
          description: "(Deprecated) Session ID to select",
        },
        id: {
          type: "string",
          description: "Session ID to select",
        },
        label: {
          type: "string",
          description: "Fuzzy match session label",
        },
        cwd: {
          type: "string",
          description: "Fuzzy match session cwd",
        },
        index: {
          type: "number",
          description: "1-based index (sorted by last_seen desc)",
        },
      },
      required: [],
    },
  },
  {
    name: "buddy_session_info",
    description:
      "Get information about the currently selected buddy.nvim session",
    inputSchema: {
      type: "object" as const,
      properties: {},
      required: [],
    },
  },
  {
    name: "buddy_refresh",
    description:
      "Refresh the sessions list and reconnect to the current session if still available",
    inputSchema: {
      type: "object" as const,
      properties: {},
      required: [],
    },
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// Downstream Client Manager
// ─────────────────────────────────────────────────────────────────────────────

class DownstreamManager {
  private client: Client | null = null;
  private transport: SSEClientTransport | null = null;
  private currentSession: BuddySession | null = null;
  private cachedTools: Tool[] = [];

  async connect(session: BuddySession): Promise<void> {
    await this.disconnect();

    const url = `http://${session.host || "127.0.0.1"}:${session.port}/sse`;
    log("info", `Connecting to downstream: ${url}`);

    try {
      this.transport = new SSEClientTransport(new URL(url));
      this.client = new Client(
        { name: "buddy-mcp-proxy", version: "0.1.0" },
        { capabilities: {} }
      );

      await this.client.connect(this.transport);
      this.currentSession = session;

      // Fetch and cache tools
      await this.refreshTools();

      log("info", `Connected to session ${session.id} on port ${session.port}`);
    } catch (err) {
      log("error", `Failed to connect to ${url}`, err);
      await this.disconnect();
      throw err;
    }
  }

  async disconnect(): Promise<void> {
    if (this.transport) {
      try {
        await this.transport.close();
      } catch {
        // Ignore close errors
      }
    }
    this.client = null;
    this.transport = null;
    this.currentSession = null;
    this.cachedTools = [];
  }

  async refreshTools(): Promise<void> {
    if (!this.client) {
      this.cachedTools = [];
      return;
    }

    try {
      const result = await this.client.listTools();
      this.cachedTools = result.tools || [];
      log("info", `Fetched ${this.cachedTools.length} tools from downstream`);
    } catch (err) {
      log("error", "Failed to fetch downstream tools", err);
      this.cachedTools = [];
    }
  }

  async callTool(
    name: string,
    args: Record<string, unknown>
  ): Promise<CallToolResult> {
    if (!this.client) {
      throw new Error("No downstream session connected");
    }

    try {
      const result = await this.client.callTool({ name, arguments: args });
      // SDK client returns CompatibilityCallToolResult which may have toolResult instead of content
      // Normalize to CallToolResult format
      if ("content" in result) {
        return result as CallToolResult;
      }
      // Handle legacy format with toolResult
      if ("toolResult" in result) {
        const toolResult = result.toolResult;
        return {
          content: [
            {
              type: "text" as const,
              text:
                typeof toolResult === "string"
                  ? toolResult
                  : JSON.stringify(toolResult, null, 2),
            },
          ],
        };
      }
      // Fallback
      return {
        content: [
          { type: "text" as const, text: JSON.stringify(result, null, 2) },
        ],
      };
    } catch (err) {
      log("error", `Failed to call tool ${name}`, err);
      // Check if connection is dead
      await this.checkHealth();
      throw err;
    }
  }

  async checkHealth(): Promise<boolean> {
    if (!this.client || !this.currentSession) {
      return false;
    }

    try {
      // Try to list tools as a health check
      await this.client.listTools();
      return true;
    } catch {
      log("warn", "Downstream connection is dead, clearing selection");
      await this.disconnect();
      return false;
    }
  }

  getTools(): Tool[] {
    return this.cachedTools;
  }

  getCurrentSession(): BuddySession | null {
    return this.currentSession;
  }

  isConnected(): boolean {
    return this.client !== null && this.currentSession !== null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MCP Server
// ─────────────────────────────────────────────────────────────────────────────

async function main() {
  log("info", "Starting buddy-mcp-proxy");

  const downstream = new DownstreamManager();

  const server = new Server(
    { name: "buddy-mcp-proxy", version: "0.1.0" },
    { capabilities: { tools: { listChanged: true } } }
  );

  // Helper to notify tools changed
  const notifyToolsChanged = async () => {
    try {
      await server.notification({
        method: "notifications/tools/list_changed",
      });
      log("info", "Sent tools/list_changed notification");
    } catch (err) {
      log("error", "Failed to send tools/list_changed notification", err);
    }
  };

  // Handle tools/list
  server.setRequestHandler(ListToolsRequestSchema, async () => {
    // Check downstream health before listing
    if (downstream.isConnected()) {
      await downstream.checkHealth();
    }

    const downstreamTools = downstream.getTools();
    const allTools = [...META_TOOLS, ...downstreamTools];

    log(
      "info",
      `Returning ${allTools.length} tools (${META_TOOLS.length} meta + ${downstreamTools.length} downstream)`
    );

    return { tools: allTools };
  });

  // Handle tools/call
  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args = {} } = request.params;

    log("info", `Tool call: ${name}`);

    // Handle meta-tools
    if (name === "buddy_sessions_list") {
      const sessions = loadSessions();
      const currentId = downstream.getCurrentSession()?.id;
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(
              {
                sessions: sessions
                  .sort((a, b) => (b.last_seen ?? 0) - (a.last_seen ?? 0))
                  .map((s) => ({
                    id: s.id,
                    label: s.label ?? null,
                    host: s.host,
                    port: s.port,
                    cwd: s.cwd,
                    pid: s.pid,
                    started_at: s.started_at,
                    last_seen: s.last_seen,
                    url: `http://${s.host}:${s.port}/sse`,
                    selected: s.id === currentId,
                  })),
                current_session_id: currentId || null,
              },
              null,
              2
            ),
          },
        ],
      };
    }

    if (name === "buddy_session_select") {
      const selector = {
        id: (args.session_id as string) || (args.id as string) || undefined,
        label: (args.label as string) || undefined,
        cwd: (args.cwd as string) || undefined,
        index:
          typeof (args.index as unknown) === "number"
            ? (args.index as number)
            : undefined,
      };

      if (!selector.id && !selector.label && !selector.cwd && !selector.index) {
        return {
          content: [
            {
              type: "text" as const,
              text: "Error: provide one of: id, session_id, label, cwd, index",
            },
          ],
          isError: true,
        };
      }

      const sessions = loadSessions();
      const session = resolveSession(sessions, selector);

      if (!session) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Error: Session not found for selector ${JSON.stringify(selector)}`,
            },
          ],
          isError: true,
        };
      }

      try {
        await downstream.connect(session);
        await notifyToolsChanged();
        return {
          content: [
            {
              type: "text" as const,
              text: `Connected to session '${session.id}' at http://${session.host}:${session.port}. ${downstream.getTools().length} tools now available.`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Error connecting to session '${session.id}': ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
          isError: true,
        };
      }
    }

    if (name === "buddy_session_info") {
      const session = downstream.getCurrentSession();
      if (!session) {
        return {
          content: [
            { type: "text" as const, text: "No session currently selected" },
          ],
        };
      }

      const tools = downstream.getTools();
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(
              {
                id: session.id,
                port: session.port,
                cwd: session.cwd,
                pid: session.pid,
                started_at: session.started_at,
                tools_count: tools.length,
                tools: tools.map((t) => t.name),
              },
              null,
              2
            ),
          },
        ],
      };
    }

    if (name === "buddy_refresh") {
      const currentSession = downstream.getCurrentSession();
      const sessions = loadSessions();

      if (currentSession) {
        // Check if current session still exists
        const stillExists = sessions.find((s) => s.id === currentSession.id);
        if (stillExists) {
          // Try to refresh connection
          const healthy = await downstream.checkHealth();
          if (!healthy) {
            // Attempt reconnect
            try {
              await downstream.connect(stillExists);
            } catch {
              // Connection failed, already disconnected
            }
          } else {
            await downstream.refreshTools();
          }
        } else {
          await downstream.disconnect();
        }
        await notifyToolsChanged();
      }

      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(
              {
                sessions_count: sessions.length,
                current_session: downstream.getCurrentSession()?.id || null,
                connected: downstream.isConnected(),
                tools_count: downstream.getTools().length,
              },
              null,
              2
            ),
          },
        ],
      };
    }

    // Forward to downstream
    if (!downstream.isConnected()) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error: No buddy.nvim session selected. Use buddy_sessions_list and buddy_session_select first.`,
          },
        ],
        isError: true,
      };
    }

    try {
      const result = await downstream.callTool(name, args as Record<string, unknown>);
      return result;
    } catch (err) {
      // If downstream died, notify
      if (!downstream.isConnected()) {
        await notifyToolsChanged();
      }
      return {
        content: [
          {
            type: "text" as const,
            text: `Error calling tool '${name}': ${err instanceof Error ? err.message : String(err)}`,
          },
        ],
        isError: true,
      };
    }
  });

  // Start the server
  const transport = new StdioServerTransport();
  await server.connect(transport);

  log("info", "buddy-mcp-proxy running on stdio");

  // Handle shutdown
  process.on("SIGINT", async () => {
    log("info", "Shutting down...");
    await downstream.disconnect();
    await server.close();
    process.exit(0);
  });

  process.on("SIGTERM", async () => {
    log("info", "Shutting down...");
    await downstream.disconnect();
    await server.close();
    process.exit(0);
  });
}

main().catch((err) => {
  log("error", "Fatal error", err);
  process.exit(1);
});
