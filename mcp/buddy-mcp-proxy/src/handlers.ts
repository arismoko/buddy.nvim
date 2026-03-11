import type { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { DownstreamManager } from "./downstream.js";
import { getNoSessionsHint } from "./install-check.js";
import { log } from "./logger.js";
import { META_TOOLS } from "./meta-tools.js";
import { textError, textResult } from "./results.js";
import { getSessionUrl, loadSessions, resolveSession, sortSessionsByLastSeen } from "./sessions.js";
import { SessionPoller } from "./poller.js";
import type { BuddySession, SessionSelector } from "./types.js";

function formatAvailableSessions(sessions: BuddySession[]): string {
  return sortSessionsByLastSeen(sessions)
    .map((session) => `  - ${session.id} (cwd: ${session.cwd}${session.label ? `, label: ${session.label}` : ""})`)
    .join("\n");
}

function buildSelectSelector(args: Record<string, unknown>): SessionSelector {
  return {
    id: (args.session_id as string) || (args.id as string) || undefined,
    label: (args.label as string) || undefined,
    cwd: (args.cwd as string) || undefined,
    index: typeof args.index === "number" ? args.index : undefined,
  };
}

export function registerHandlers(
  server: Server,
  downstream: DownstreamManager,
  poller: SessionPoller,
  notifyToolsChanged: () => Promise<void>,
): void {
  server.setRequestHandler(ListToolsRequestSchema, async () => {
    if (downstream.isConnected()) {
      const healthy = await downstream.checkHealth();
      if (!healthy) poller.ensure();
    }

    const downstreamTools = downstream.getTools();
    const allTools = [...META_TOOLS, ...downstreamTools];
    log("info", `Returning ${allTools.length} tools (${META_TOOLS.length} meta + ${downstreamTools.length} downstream)`);
    return { tools: allTools };
  });

  server.setRequestHandler(
    CallToolRequestSchema,
    async (request: { params: { name: string; arguments?: Record<string, unknown> } }) => {
    const { name, arguments: rawArgs = {} } = request.params;
    const args = rawArgs as Record<string, unknown>;
    log("info", `Tool call: ${name}`);

    if (name === "buddy_sessions_list") {
      const sessions = loadSessions();
      const currentId = downstream.getCurrentSession()?.id;
      if (sessions.length === 0) {
        return textResult(`No buddy.nvim sessions found.\n${await getNoSessionsHint()}`);
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
              selected: session.id === currentId,
            })),
            current_session_id: currentId || null,
          },
          null,
          2,
        ),
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
        const available = sessions.length > 0 ? `\nAvailable sessions:\n${formatAvailableSessions(sessions)}` : "";
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
      if (!session) return textResult("No session currently selected");
      return textResult(
        JSON.stringify(
          {
            id: session.id,
            port: session.port,
            cwd: session.cwd,
            pid: session.pid,
            started_at: session.started_at,
            tools_count: downstream.getTools().length,
            tools: downstream.getTools().map((tool) => tool.name),
          },
          null,
          2,
        ),
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
            tools_count: downstream.getTools().length,
          },
          null,
          2,
        ),
      );
    }

    if (!downstream.isConnected()) {
      const sessions = loadSessions();
      const hint = sessions.length === 0
        ? await getNoSessionsHint()
        : `\n\nAvailable sessions (use buddy_session_select to connect):\n${formatAvailableSessions(sessions)}`;
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
    },
  );
}
