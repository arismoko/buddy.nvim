#!/usr/bin/env node

// src/index.ts
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

// src/downstream.ts
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { SSEClientTransport } from "@modelcontextprotocol/sdk/client/sse.js";
import { ToolListChangedNotificationSchema } from "@modelcontextprotocol/sdk/types.js";

// src/logger.ts
function log(level, message, data) {
  const line = `[${(/* @__PURE__ */ new Date()).toISOString()}] [${level.toUpperCase()}] ${message}`;
  if (data !== void 0) {
    console.error(line, data);
    return;
  }
  console.error(line);
}

// src/sessions.ts
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
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
    return maybeArray.sessions.filter((session) => !!session && typeof session.id === "string").map((session) => ({
      ...session,
      host: session.host || "127.0.0.1"
    }));
  }
  const maybeV1 = raw;
  if (maybeV1.sessions && typeof maybeV1.sessions === "object") {
    return Object.entries(maybeV1.sessions).flatMap(([id, session]) => {
      const host = String(session.host || "127.0.0.1");
      const port = Number(session.port);
      const cwd = String(session.cwd || "");
      if (!id || !Number.isFinite(port) || !cwd)
        return [];
      return [
        {
          id,
          host,
          port,
          cwd,
          label: session.label ?? null,
          pid: typeof session.pid === "number" ? session.pid : void 0,
          auth_token: typeof session.auth_token === "string" ? session.auth_token : void 0,
          started_at: session.started_at,
          last_seen: typeof session.last_seen === "number" ? session.last_seen : void 0
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
    return normalizeSessions(JSON.parse(fs.readFileSync(sessionsPath, "utf-8")));
  } catch (error) {
    log("error", `Failed to load sessions from ${sessionsPath}`, error);
    return [];
  }
}
function sortSessionsByLastSeen(sessions) {
  return [...sessions].sort((a, b) => (b.last_seen ?? 0) - (a.last_seen ?? 0));
}
function getSessionUrl(session) {
  return `http://${session.host || "127.0.0.1"}:${session.port}/sse`;
}
function fuzzyIncludes(haystack, needle) {
  return haystack.toLowerCase().includes(needle.toLowerCase());
}
function resolveSession(sessions, selector) {
  if (selector.id) {
    return sessions.find((session) => session.id === selector.id) ?? null;
  }
  if (typeof selector.index === "number") {
    return sortSessionsByLastSeen(sessions)[selector.index - 1] ?? null;
  }
  if (selector.label) {
    const matches = sessions.filter(
      (session) => session.label ? fuzzyIncludes(String(session.label), selector.label) : false
    );
    return sortSessionsByLastSeen(matches)[0] ?? null;
  }
  if (selector.cwd) {
    const matches = sessions.filter((session) => fuzzyIncludes(session.cwd, selector.cwd));
    return sortSessionsByLastSeen(matches)[0] ?? null;
  }
  return null;
}

// src/version.ts
var PROXY_NAME = "buddy-mcp-proxy";
var PROXY_VERSION = "0.1.2";

// src/downstream.ts
var DownstreamManager = class {
  client = null;
  transport = null;
  currentSession = null;
  cachedTools = [];
  onToolsChanged = null;
  setOnToolsChanged(callback) {
    this.onToolsChanged = callback;
  }
  async connect(session) {
    await this.disconnect();
    const url = getSessionUrl(session);
    log("info", `Connecting to downstream: ${url}`);
    try {
      const transportOptions = {};
      if (session.auth_token) {
        transportOptions.requestInit = {
          headers: { Authorization: `Bearer ${session.auth_token}` }
        };
      }
      this.transport = new SSEClientTransport(new URL(url), transportOptions);
      this.client = new Client({ name: PROXY_NAME, version: PROXY_VERSION }, { capabilities: {} });
      await this.client.connect(this.transport);
      this.currentSession = session;
      this.client.setNotificationHandler(ToolListChangedNotificationSchema, async () => {
        log("info", "Downstream tools changed, refreshing...");
        await this.refreshTools();
        if (this.onToolsChanged) {
          await this.onToolsChanged();
        }
      });
      await this.refreshTools();
      log("info", `Connected to session ${session.id} on port ${session.port}`);
    } catch (error) {
      log("error", `Failed to connect to ${url}`, error);
      await this.disconnect();
      throw error;
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
    } catch (error) {
      log("error", "Failed to fetch downstream tools", error);
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
          content: [{ type: "text", text: typeof toolResult === "string" ? toolResult : JSON.stringify(toolResult, null, 2) }]
        };
      }
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    } catch (error) {
      log("error", `Failed to call tool ${name}`, error);
      await this.checkHealth();
      throw error;
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

// src/handlers.ts
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";

// src/install-check.ts
import * as fs2 from "node:fs";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
var execFileAsync = promisify(execFile);
var buddyInstallStatus = null;
var buddyInstallCheckPromise = null;
async function checkBuddyInstalled() {
  if (buddyInstallStatus !== null) {
    return buddyInstallStatus;
  }
  if (!buddyInstallCheckPromise) {
    buddyInstallCheckPromise = (async () => {
      try {
        const { stdout } = await execFileAsync(
          "nvim",
          [
            "--headless",
            "-c",
            "lua local ok,_=pcall(require,'buddy'); print(ok and 'BUDDY_OK' or 'BUDDY_MISSING')",
            "-c",
            "qa!"
          ],
          { timeout: 1e4 }
        );
        buddyInstallStatus = stdout.includes("BUDDY_OK") ? "installed" : "missing";
        log(buddyInstallStatus === "installed" ? "info" : "warn", `buddy.nvim install check: ${buddyInstallStatus}`);
      } catch (error) {
        log("error", "buddy.nvim install check failed (nvim not found?)", error);
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
  const lines = ["", "-- Troubleshooting --"];
  if (status === "missing") {
    lines.push("buddy.nvim is NOT installed in Neovim.");
    lines.push("Install it first: https://github.com/arismoko/buddy.nvim#installation");
  } else if (status === "installed") {
    lines.push("buddy.nvim is installed in Neovim.");
    lines.push("");
    lines.push("To start a buddy server, do ONE of:");
    lines.push('  - Open Neovim with auto_start enabled: require("buddy").setup({ auto_start = true })');
    lines.push('  - Start manually inside Neovim: :lua require("buddy").start()');
  } else {
    lines.push("Could not detect whether buddy.nvim is installed (nvim not found on PATH).");
    lines.push("");
    lines.push("If buddy.nvim is installed, start a server:");
    lines.push('  - Open Neovim with auto_start enabled: require("buddy").setup({ auto_start = true })');
    lines.push('  - Start manually inside Neovim: :lua require("buddy").start()');
  }
  lines.push("");
  lines.push(`Sessions file: ${sessionsPath}`);
  lines.push(fs2.existsSync(sessionsPath) ? "  - File exists" : "  - File does not exist yet");
  return lines.join("\n");
}

// src/meta-tools.ts
var META_TOOLS = [
  {
    name: "buddy_sessions_list",
    description: "List all available buddy.nvim sessions from the sessions registry",
    inputSchema: { type: "object", properties: {}, required: [] }
  },
  {
    name: "buddy_session_select",
    description: "Select a buddy.nvim session by ID to connect to. This will expose that session's tools.",
    inputSchema: {
      type: "object",
      properties: {
        session_id: { type: "string", description: "(Deprecated) Session ID to select" },
        id: { type: "string", description: "Session ID to select" },
        label: { type: "string", description: "Fuzzy match session label" },
        cwd: { type: "string", description: "Fuzzy match session cwd" },
        index: { type: "number", description: "1-based index (sorted by last_seen desc)" }
      },
      required: []
    }
  },
  {
    name: "buddy_session_info",
    description: "Get information about the currently selected buddy.nvim session",
    inputSchema: { type: "object", properties: {}, required: [] }
  },
  {
    name: "buddy_refresh",
    description: "Refresh the sessions list and reconnect to the current session if still available",
    inputSchema: { type: "object", properties: {}, required: [] }
  }
];

// src/results.ts
function textResult(text) {
  return { content: [{ type: "text", text }] };
}
function textError(text) {
  return { content: [{ type: "text", text }], isError: true };
}

// src/handlers.ts
function formatAvailableSessions(sessions) {
  return sortSessionsByLastSeen(sessions).map((session) => `  - ${session.id} (cwd: ${session.cwd}${session.label ? `, label: ${session.label}` : ""})`).join("\n");
}
function buildSelectSelector(args) {
  return {
    id: args.session_id || args.id || void 0,
    label: args.label || void 0,
    cwd: args.cwd || void 0,
    index: typeof args.index === "number" ? args.index : void 0
  };
}
function registerHandlers(server, downstream, poller, notifyToolsChanged) {
  server.setRequestHandler(ListToolsRequestSchema, async () => {
    if (downstream.isConnected()) {
      const healthy = await downstream.checkHealth();
      if (!healthy)
        poller.ensure();
    }
    const downstreamTools = downstream.getTools();
    const allTools = [...META_TOOLS, ...downstreamTools];
    log("info", `Returning ${allTools.length} tools (${META_TOOLS.length} meta + ${downstreamTools.length} downstream)`);
    return { tools: allTools };
  });
  server.setRequestHandler(
    CallToolRequestSchema,
    async (request) => {
      const { name, arguments: rawArgs = {} } = request.params;
      const args = rawArgs;
      log("info", `Tool call: ${name}`);
      if (name === "buddy_sessions_list") {
        const sessions = loadSessions();
        const currentId = downstream.getCurrentSession()?.id;
        if (sessions.length === 0) {
          return textResult(`No buddy.nvim sessions found.
${await getNoSessionsHint()}`);
        }
        return textResult(
          JSON.stringify(
            {
              sessions: sortSessionsByLastSeen(sessions).map((session) => ({
                id: session.id,
                label: session.label ?? null,
                host: session.host,
                port: session.port,
                cwd: session.cwd,
                pid: session.pid,
                started_at: session.started_at,
                last_seen: session.last_seen,
                url: getSessionUrl(session),
                selected: session.id === currentId
              })),
              current_session_id: currentId || null
            },
            null,
            2
          )
        );
      }
      if (name === "buddy_session_select") {
        const selector = buildSelectSelector(args);
        if (!selector.id && !selector.label && !selector.cwd && !selector.index) {
          return textError("Error: provide one of: id, session_id, label, cwd, index");
        }
        const sessions = loadSessions();
        const session = resolveSession(sessions, selector);
        if (!session) {
          const hint = sessions.length === 0 ? await getNoSessionsHint() : "";
          const available = sessions.length > 0 ? `
Available sessions:
${formatAvailableSessions(sessions)}` : "";
          return textError(`Error: Session not found for selector ${JSON.stringify(selector)}${available}${hint}`);
        }
        try {
          await downstream.connect(session);
          poller.stop();
          await notifyToolsChanged();
          return textResult(`Connected to session '${session.id}' at ${getSessionUrl(session)}. ${downstream.getTools().length} tools now available.`);
        } catch (error) {
          return textError(`Error connecting to session '${session.id}': ${error instanceof Error ? error.message : String(error)}`);
        }
      }
      if (name === "buddy_session_info") {
        const session = downstream.getCurrentSession();
        if (!session)
          return textResult("No session currently selected");
        return textResult(
          JSON.stringify(
            {
              id: session.id,
              port: session.port,
              cwd: session.cwd,
              pid: session.pid,
              started_at: session.started_at,
              tools_count: downstream.getTools().length,
              tools: downstream.getTools().map((tool) => tool.name)
            },
            null,
            2
          )
        );
      }
      if (name === "buddy_refresh") {
        const currentSession = downstream.getCurrentSession();
        const sessions = loadSessions();
        if (currentSession) {
          const stillExists = sessions.find((session) => session.id === currentSession.id);
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
        return textResult(
          JSON.stringify(
            {
              sessions_count: sessions.length,
              current_session: downstream.getCurrentSession()?.id || null,
              connected: downstream.isConnected(),
              tools_count: downstream.getTools().length
            },
            null,
            2
          )
        );
      }
      if (!downstream.isConnected()) {
        const sessions = loadSessions();
        const hint = sessions.length === 0 ? await getNoSessionsHint() : `

Available sessions (use buddy_session_select to connect):
${formatAvailableSessions(sessions)}`;
        return textError(`Error: No buddy.nvim session selected. Use buddy_sessions_list and buddy_session_select first.${hint}`);
      }
      try {
        return await downstream.callTool(name, args);
      } catch (error) {
        if (!downstream.isConnected()) {
          await notifyToolsChanged();
          poller.ensure();
        }
        return textError(`Error calling tool '${name}': ${error instanceof Error ? error.message : String(error)}`);
      }
    }
  );
}

// src/poller.ts
var SessionPoller = class _SessionPoller {
  static BACKOFF_MS = 3e4;
  timer = null;
  connecting = false;
  failedSessions = /* @__PURE__ */ new Map();
  intervalMs;
  downstream;
  onConnected;
  constructor(options) {
    this.downstream = options.downstream;
    this.intervalMs = options.intervalMs ?? 3e3;
    this.onConnected = options.onConnected;
  }
  start() {
    if (this.timer)
      return;
    log("info", `Session poller started (every ${this.intervalMs}ms)`);
    this.timer = setInterval(() => void this.poll(), this.intervalMs);
    void this.poll();
  }
  stop() {
    if (!this.timer)
      return;
    clearInterval(this.timer);
    this.timer = null;
    log("info", "Session poller stopped");
  }
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
    const sorted = sortSessionsByLastSeen(sessions);
    const now = Date.now();
    let candidates = sorted.filter((session) => {
      const failedAt = this.failedSessions.get(session.id);
      return failedAt === void 0 || now - failedAt >= _SessionPoller.BACKOFF_MS;
    });
    if (candidates.length === 0) {
      log("info", "All sessions in backoff - clearing failed set and retrying");
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
    } catch (error) {
      this.failedSessions.set(target.id, Date.now());
      log("warn", `Auto-connect to ${target.id} failed (backoff ${_SessionPoller.BACKOFF_MS}ms), will try next session`, error);
    } finally {
      this.connecting = false;
    }
  }
};

// src/index.ts
async function main() {
  log("info", `Starting ${PROXY_NAME}`);
  const downstream = new DownstreamManager();
  const server = new Server(
    { name: PROXY_NAME, version: PROXY_VERSION },
    { capabilities: { tools: { listChanged: true } } }
  );
  const notifyToolsChanged = async () => {
    try {
      await server.notification({ method: "notifications/tools/list_changed" });
      log("info", "Sent tools/list_changed notification");
    } catch (error) {
      log("error", "Failed to send tools/list_changed notification", error);
    }
  };
  downstream.setOnToolsChanged(notifyToolsChanged);
  const poller = new SessionPoller({
    downstream,
    onConnected: notifyToolsChanged
  });
  registerHandlers(server, downstream, poller, notifyToolsChanged);
  poller.start();
  const transport = new StdioServerTransport();
  await server.connect(transport);
  log("info", `${PROXY_NAME} running on stdio`);
  const shutdown = async () => {
    log("info", "Shutting down...");
    poller.stop();
    await downstream.disconnect();
    await server.close();
    process.exit(0);
  };
  process.on("SIGINT", () => void shutdown());
  process.on("SIGTERM", () => void shutdown());
}
main().catch((error) => {
  log("error", "Fatal error", error);
  process.exit(1);
});
