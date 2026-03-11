import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { log } from "./logger.js";
import type { BuddySession, SessionSelector, SessionsRegistryLegacyArray, SessionsRegistryV1 } from "./types.js";

export function getSessionsPath(): string {
  const xdgState = process.env.XDG_STATE_HOME;
  if (xdgState) {
    return path.join(xdgState, "nvim", "buddy", "sessions.json");
  }
  return path.join(os.homedir(), ".local", "state", "nvim", "buddy", "sessions.json");
}

function normalizeSessions(raw: unknown): BuddySession[] {
  if (!raw || typeof raw !== "object") return [];

  const maybeArray = raw as SessionsRegistryLegacyArray;
  if (Array.isArray(maybeArray.sessions)) {
    return maybeArray.sessions
      .filter((session): session is BuddySession => !!session && typeof session.id === "string")
      .map((session) => ({
        ...session,
        host: session.host || "127.0.0.1",
      }));
  }

  const maybeV1 = raw as SessionsRegistryV1;
  if (maybeV1.sessions && typeof maybeV1.sessions === "object") {
    return Object.entries(maybeV1.sessions).flatMap(([id, session]) => {
      const host = String(session.host || "127.0.0.1");
      const port = Number(session.port);
      const cwd = String(session.cwd || "");
      if (!id || !Number.isFinite(port) || !cwd) return [];
      return [
        {
          id,
          host,
          port,
          cwd,
          label: session.label ?? null,
          pid: typeof session.pid === "number" ? session.pid : undefined,
          auth_token: typeof session.auth_token === "string" ? session.auth_token : undefined,
          started_at: session.started_at,
          last_seen: typeof session.last_seen === "number" ? session.last_seen : undefined,
        } satisfies BuddySession,
      ];
    });
  }

  return [];
}

export function loadSessions(): BuddySession[] {
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

export function sortSessionsByLastSeen(sessions: BuddySession[]): BuddySession[] {
  return [...sessions].sort((a, b) => (b.last_seen ?? 0) - (a.last_seen ?? 0));
}

export function getSessionUrl(session: BuddySession): string {
  return `http://${session.host || "127.0.0.1"}:${session.port}/sse`;
}

function fuzzyIncludes(haystack: string, needle: string): boolean {
  return haystack.toLowerCase().includes(needle.toLowerCase());
}

export function resolveSession(
  sessions: BuddySession[],
  selector: SessionSelector,
): BuddySession | null {
  if (selector.id) {
    return sessions.find((session) => session.id === selector.id) ?? null;
  }

  if (typeof selector.index === "number") {
    return sortSessionsByLastSeen(sessions)[selector.index - 1] ?? null;
  }

  if (selector.label) {
    const matches = sessions.filter((session) =>
      session.label ? fuzzyIncludes(String(session.label), selector.label!) : false,
    );
    return sortSessionsByLastSeen(matches)[0] ?? null;
  }

  if (selector.cwd) {
    const matches = sessions.filter((session) => fuzzyIncludes(session.cwd, selector.cwd!));
    return sortSessionsByLastSeen(matches)[0] ?? null;
  }

  return null;
}
