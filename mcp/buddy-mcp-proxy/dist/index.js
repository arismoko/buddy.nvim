#!/usr/bin/env node

// src/index.ts
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { SSEClientTransport } from "@modelcontextprotocol/sdk/client/sse.js";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema
} from "@modelcontextprotocol/sdk/types.js";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
function log(level, msg, data) {
  const timestamp = (/* @__PURE__ */ new Date()).toISOString();
  const line = `[${timestamp}] [${level.toUpperCase()}] ${msg}`;
  if (data !== void 0) {
    console.error(line, data);
  } else {
    console.error(line);
  }
}
function getSessionsPath() {
  const xdgState = process.env.XDG_STATE_HOME;
  if (xdgState) {
    return path.join(xdgState, "nvim", "buddy", "sessions.json");
  }
  return path.join(os.homedir(), ".local", "state", "nvim", "buddy", "sessions.json");
}
function normalizeSessions(raw) {
  if (!raw || typeof raw !== "object")
    return [];
  const maybeArray = raw;
  if (Array.isArray(maybeArray.sessions)) {
    return maybeArray.sessions.filter((s) => !!s && typeof s.id === "string").map((s) => ({
      ...s,
      host: s.host || "127.0.0.1"
    }));
  }
  const maybeV1 = raw;
  if (maybeV1.sessions && typeof maybeV1.sessions === "object") {
    return Object.entries(maybeV1.sessions).flatMap(([id, s]) => {
      const host = s.host || "127.0.0.1";
      const port = Number(s.port);
      const cwd = String(s.cwd || "");
      if (!id || !Number.isFinite(port) || !cwd)
        return [];
      return [
        {
          id,
          host,
          port,
          cwd,
          label: s.label ?? null,
          pid: typeof s.pid === "number" ? s.pid : void 0,
          started_at: s.started_at,
          last_seen: typeof s.last_seen === "number" ? s.last_seen : void 0
        }
      ];
    });
  }
  return [];
}
function loadSessions() {
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
function fuzzyIncludes(haystack, needle) {
  return haystack.toLowerCase().includes(needle.toLowerCase());
}
function resolveSession(sessions, selector) {
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
    const matches = sessions.filter(
      (s) => s.label ? fuzzyIncludes(String(s.label), selector.label) : false
    );
    if (matches.length === 1)
      return matches[0];
    if (matches.length > 1) {
      matches.sort((a, b) => (b.last_seen ?? 0) - (a.last_seen ?? 0));
      return matches[0];
    }
  }
  if (selector.cwd) {
    const matches = sessions.filter((s) => fuzzyIncludes(s.cwd, selector.cwd));
    if (matches.length === 1)
      return matches[0];
    if (matches.length > 1) {
      matches.sort((a, b) => (b.last_seen ?? 0) - (a.last_seen ?? 0));
      return matches[0];
    }
  }
  return null;
}
var META_TOOLS = [
  {
    name: "buddy_sessions_list",
    description: "List all available buddy.nvim sessions from the sessions registry",
    inputSchema: {
      type: "object",
      properties: {},
      required: []
    }
  },
  {
    name: "buddy_session_select",
    description: "Select a buddy.nvim session by ID to connect to. This will expose that session's tools.",
    inputSchema: {
      type: "object",
      properties: {
        session_id: {
          type: "string",
          description: "(Deprecated) Session ID to select"
        },
        id: {
          type: "string",
          description: "Session ID to select"
        },
        label: {
          type: "string",
          description: "Fuzzy match session label"
        },
        cwd: {
          type: "string",
          description: "Fuzzy match session cwd"
        },
        index: {
          type: "number",
          description: "1-based index (sorted by last_seen desc)"
        }
      },
      required: []
    }
  },
  {
    name: "buddy_session_info",
    description: "Get information about the currently selected buddy.nvim session",
    inputSchema: {
      type: "object",
      properties: {},
      required: []
    }
  },
  {
    name: "buddy_refresh",
    description: "Refresh the sessions list and reconnect to the current session if still available",
    inputSchema: {
      type: "object",
      properties: {},
      required: []
    }
  }
];
var DownstreamManager = class {
  client = null;
  transport = null;
  currentSession = null;
  cachedTools = [];
  async connect(session) {
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
      await this.refreshTools();
      log("info", `Connected to session ${session.id} on port ${session.port}`);
    } catch (err) {
      log("error", `Failed to connect to ${url}`, err);
      await this.disconnect();
      throw err;
    }
  }
  async disconnect() {
    if (this.transport) {
      try {
        await this.transport.close();
      } catch {
      }
    }
    this.client = null;
    this.transport = null;
    this.currentSession = null;
    this.cachedTools = [];
  }
  async refreshTools() {
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
  async callTool(name, args) {
    if (!this.client) {
      throw new Error("No downstream session connected");
    }
    try {
      const result = await this.client.callTool({ name, arguments: args });
      if ("content" in result) {
        return result;
      }
      if ("toolResult" in result) {
        const toolResult = result.toolResult;
        return {
          content: [
            {
              type: "text",
              text: typeof toolResult === "string" ? toolResult : JSON.stringify(toolResult, null, 2)
            }
          ]
        };
      }
      return {
        content: [
          { type: "text", text: JSON.stringify(result, null, 2) }
        ]
      };
    } catch (err) {
      log("error", `Failed to call tool ${name}`, err);
      await this.checkHealth();
      throw err;
    }
  }
  async checkHealth() {
    if (!this.client || !this.currentSession) {
      return false;
    }
    try {
      await this.client.listTools();
      return true;
    } catch {
      log("warn", "Downstream connection is dead, clearing selection");
      await this.disconnect();
      return false;
    }
  }
  getTools() {
    return this.cachedTools;
  }
  getCurrentSession() {
    return this.currentSession;
  }
  isConnected() {
    return this.client !== null && this.currentSession !== null;
  }
};
async function main() {
  log("info", "Starting buddy-mcp-proxy");
  const downstream = new DownstreamManager();
  const server = new Server(
    { name: "buddy-mcp-proxy", version: "0.1.0" },
    { capabilities: { tools: { listChanged: true } } }
  );
  const notifyToolsChanged = async () => {
    try {
      await server.notification({
        method: "notifications/tools/list_changed"
      });
      log("info", "Sent tools/list_changed notification");
    } catch (err) {
      log("error", "Failed to send tools/list_changed notification", err);
    }
  };
  server.setRequestHandler(ListToolsRequestSchema, async () => {
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
  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args = {} } = request.params;
    log("info", `Tool call: ${name}`);
    if (name === "buddy_sessions_list") {
      const sessions = loadSessions();
      const currentId = downstream.getCurrentSession()?.id;
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              {
                sessions: sessions.sort((a, b) => (b.last_seen ?? 0) - (a.last_seen ?? 0)).map((s) => ({
                  id: s.id,
                  label: s.label ?? null,
                  host: s.host,
                  port: s.port,
                  cwd: s.cwd,
                  pid: s.pid,
                  started_at: s.started_at,
                  last_seen: s.last_seen,
                  url: `http://${s.host}:${s.port}/sse`,
                  selected: s.id === currentId
                })),
                current_session_id: currentId || null
              },
              null,
              2
            )
          }
        ]
      };
    }
    if (name === "buddy_session_select") {
      const selector = {
        id: args.session_id || args.id || void 0,
        label: args.label || void 0,
        cwd: args.cwd || void 0,
        index: typeof args.index === "number" ? args.index : void 0
      };
      if (!selector.id && !selector.label && !selector.cwd && !selector.index) {
        return {
          content: [
            {
              type: "text",
              text: "Error: provide one of: id, session_id, label, cwd, index"
            }
          ],
          isError: true
        };
      }
      const sessions = loadSessions();
      const session = resolveSession(sessions, selector);
      if (!session) {
        return {
          content: [
            {
              type: "text",
              text: `Error: Session not found for selector ${JSON.stringify(selector)}`
            }
          ],
          isError: true
        };
      }
      try {
        await downstream.connect(session);
        await notifyToolsChanged();
        return {
          content: [
            {
              type: "text",
              text: `Connected to session '${session.id}' at http://${session.host}:${session.port}. ${downstream.getTools().length} tools now available.`
            }
          ]
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Error connecting to session '${session.id}': ${err instanceof Error ? err.message : String(err)}`
            }
          ],
          isError: true
        };
      }
    }
    if (name === "buddy_session_info") {
      const session = downstream.getCurrentSession();
      if (!session) {
        return {
          content: [
            { type: "text", text: "No session currently selected" }
          ]
        };
      }
      const tools = downstream.getTools();
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              {
                id: session.id,
                port: session.port,
                cwd: session.cwd,
                pid: session.pid,
                started_at: session.started_at,
                tools_count: tools.length,
                tools: tools.map((t) => t.name)
              },
              null,
              2
            )
          }
        ]
      };
    }
    if (name === "buddy_refresh") {
      const currentSession = downstream.getCurrentSession();
      const sessions = loadSessions();
      if (currentSession) {
        const stillExists = sessions.find((s) => s.id === currentSession.id);
        if (stillExists) {
          const healthy = await downstream.checkHealth();
          if (!healthy) {
            try {
              await downstream.connect(stillExists);
            } catch {
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
            type: "text",
            text: JSON.stringify(
              {
                sessions_count: sessions.length,
                current_session: downstream.getCurrentSession()?.id || null,
                connected: downstream.isConnected(),
                tools_count: downstream.getTools().length
              },
              null,
              2
            )
          }
        ]
      };
    }
    if (!downstream.isConnected()) {
      return {
        content: [
          {
            type: "text",
            text: `Error: No buddy.nvim session selected. Use buddy_sessions_list and buddy_session_select first.`
          }
        ],
        isError: true
      };
    }
    try {
      const result = await downstream.callTool(name, args);
      return result;
    } catch (err) {
      if (!downstream.isConnected()) {
        await notifyToolsChanged();
      }
      return {
        content: [
          {
            type: "text",
            text: `Error calling tool '${name}': ${err instanceof Error ? err.message : String(err)}`
          }
        ],
        isError: true
      };
    }
  });
  const transport = new StdioServerTransport();
  await server.connect(transport);
  log("info", "buddy-mcp-proxy running on stdio");
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
