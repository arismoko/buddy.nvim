#!/usr/bin/env node

// src/index.ts
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { SSEClientTransport } from "@modelcontextprotocol/sdk/client/sse.js";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ToolListChangedNotificationSchema
} from "@modelcontextprotocol/sdk/types.js";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
var execFileAsync = promisify(execFile);
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
var buddyInstallStatus = null;
var buddyInstallCheckPromise = null;
async function checkBuddyInstalled() {
  if (buddyInstallStatus !== null) {
    return buddyInstallStatus;
  }
  if (!buddyInstallCheckPromise) {
    buddyInstallCheckPromise = (async () => {
      try {
        const { stdout } = await execFileAsync("nvim", [
          "--headless",
          "-c",
          `lua local ok,_=pcall(require,'buddy'); print(ok and 'BUDDY_OK' or 'BUDDY_MISSING')`,
          "-c",
          "qa!"
        ], { timeout: 1e4 });
        if (stdout.includes("BUDDY_OK")) {
          buddyInstallStatus = "installed";
          log("info", "buddy.nvim install check: installed");
        } else {
          buddyInstallStatus = "missing";
          log("warn", "buddy.nvim install check: NOT installed");
        }
      } catch (err) {
        log("error", "buddy.nvim install check failed (nvim not found?)", err);
        buddyInstallStatus = "check_failed";
      }
      buddyInstallCheckPromise = null;
      return buddyInstallStatus;
    })();
  }
  return buddyInstallCheckPromise;
}
async function getNoSessionsHint() {
  const sessionsPath = getSessionsPath();
  const status = await checkBuddyInstalled();
  const lines = [];
  lines.push("");
  lines.push("\u2500\u2500 Troubleshooting \u2500\u2500");
  if (status === "missing") {
    lines.push("\u2717 buddy.nvim is NOT installed in Neovim.");
    lines.push("  Install it first: https://github.com/arismoko/buddy.nvim#installation");
  } else if (status === "installed") {
    lines.push("\u2713 buddy.nvim is installed in Neovim.");
    lines.push("");
    lines.push("To start a buddy server, do ONE of:");
    lines.push("  \u2022 Open Neovim with auto_start enabled:");
    lines.push('      require("buddy").setup({ auto_start = true })');
    lines.push("  \u2022 Or start manually inside Neovim:");
    lines.push('      :lua require("buddy").start()');
  } else {
    lines.push("? Could not detect whether buddy.nvim is installed (nvim not found on PATH).");
    lines.push("");
    lines.push("If buddy.nvim is installed, start a server:");
    lines.push("  \u2022 Open Neovim with auto_start enabled:");
    lines.push('      require("buddy").setup({ auto_start = true })');
    lines.push("  \u2022 Or start manually inside Neovim:");
    lines.push('      :lua require("buddy").start()');
  }
  lines.push("");
  lines.push(`Sessions file: ${sessionsPath}`);
  const exists = fs.existsSync(sessionsPath);
  lines.push(`  ${exists ? "\u2713 File exists" : "\u2717 File does not exist (no session has ever started)"}`);
  return lines.join("\n");
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
  onToolsChanged = null;
  setOnToolsChanged(cb) {
    this.onToolsChanged = cb;
  }
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
      this.client.setNotificationHandler(
        ToolListChangedNotificationSchema,
        async () => {
          log("info", "Downstream tools changed, refreshing...");
          await this.refreshTools();
          if (this.onToolsChanged) {
            await this.onToolsChanged();
          }
        }
      );
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
var SessionPoller = class _SessionPoller {
  static BACKOFF_MS = 3e4;
  timer = null;
  connecting = false;
  failedSessions = /* @__PURE__ */ new Map();
  intervalMs;
  downstream;
  onConnected;
  constructor(opts) {
    this.downstream = opts.downstream;
    this.intervalMs = opts.intervalMs ?? 3e3;
    this.onConnected = opts.onConnected;
  }
  start() {
    if (this.timer)
      return;
    log("info", `Session poller started (every ${this.intervalMs}ms)`);
    this.timer = setInterval(() => this.poll(), this.intervalMs);
    this.poll();
  }
  stop() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
      log("info", "Session poller stopped");
    }
  }
  /** Restart polling (e.g. after a disconnect) */
  ensure() {
    if (!this.downstream.isConnected() && !this.timer) {
      this.start();
    }
  }
  async poll() {
    if (this.downstream.isConnected() || this.connecting)
      return;
    const sessions = loadSessions();
    if (sessions.length === 0)
      return;
    const sorted = [...sessions].sort(
      (a, b) => (b.last_seen ?? 0) - (a.last_seen ?? 0)
    );
    const now = Date.now();
    let candidates = sorted.filter((s) => {
      const failedAt = this.failedSessions.get(s.id);
      return failedAt === void 0 || now - failedAt >= _SessionPoller.BACKOFF_MS;
    });
    if (candidates.length === 0) {
      log("info", "All sessions in backoff \u2014 clearing failed set and retrying");
      this.failedSessions.clear();
      candidates = sorted;
    }
    const target = candidates[0];
    this.connecting = true;
    try {
      log("info", `Auto-connecting to session ${target.id} (port ${target.port})`);
      await this.downstream.connect(target);
      this.failedSessions.clear();
      this.stop();
      await this.onConnected();
      log("info", `Auto-connected to session ${target.id}`);
    } catch (err) {
      this.failedSessions.set(target.id, Date.now());
      log("warn", `Auto-connect to ${target.id} failed (backoff ${_SessionPoller.BACKOFF_MS}ms), will try next session`, err);
    } finally {
      this.connecting = false;
    }
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
  downstream.setOnToolsChanged(notifyToolsChanged);
  const poller = new SessionPoller({
    downstream,
    onConnected: notifyToolsChanged
  });
  poller.start();
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
      if (sessions.length === 0) {
        const hint = await getNoSessionsHint();
        return {
          content: [
            {
              type: "text",
              text: `No buddy.nvim sessions found.
${hint}`
            }
          ]
        };
      }
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
        const hint = sessions.length === 0 ? await getNoSessionsHint() : "";
        const availableInfo = sessions.length > 0 ? `
Available sessions:
${sessions.map((s) => `  \u2022 ${s.id} (cwd: ${s.cwd}${s.label ? `, label: ${s.label}` : ""})`).join("\n")}` : "";
        return {
          content: [
            {
              type: "text",
              text: `Error: Session not found for selector ${JSON.stringify(selector)}${availableInfo}${hint}`
            }
          ],
          isError: true
        };
      }
      try {
        await downstream.connect(session);
        poller.stop();
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
              poller.ensure();
            }
          } else {
            await downstream.refreshTools();
          }
        } else {
          await downstream.disconnect();
          poller.ensure();
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
      const sessions = loadSessions();
      let hint;
      if (sessions.length === 0) {
        hint = await getNoSessionsHint();
      } else {
        hint = `

Available sessions (use buddy_session_select to connect):
${sessions.sort((a, b) => (b.last_seen ?? 0) - (a.last_seen ?? 0)).map((s) => `  \u2022 ${s.id} (cwd: ${s.cwd}${s.label ? `, label: ${s.label}` : ""})`).join("\n")}`;
      }
      return {
        content: [
          {
            type: "text",
            text: `Error: No buddy.nvim session selected. Use buddy_sessions_list and buddy_session_select first.${hint}`
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
        poller.ensure();
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
    poller.stop();
    await downstream.disconnect();
    await server.close();
    process.exit(0);
  });
  process.on("SIGTERM", async () => {
    log("info", "Shutting down...");
    poller.stop();
    await downstream.disconnect();
    await server.close();
    process.exit(0);
  });
}
main().catch((err) => {
  log("error", "Fatal error", err);
  process.exit(1);
});
