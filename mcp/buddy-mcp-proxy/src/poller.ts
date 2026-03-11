import { log } from "./logger.js";
import { loadSessions, sortSessionsByLastSeen } from "./sessions.js";
import { DownstreamManager } from "./downstream.js";

type SessionPollerOptions = {
  downstream: DownstreamManager;
  intervalMs?: number;
  onConnected: () => Promise<void>;
};

export class SessionPoller {
  private static readonly BACKOFF_MS = 30_000;
  private timer: ReturnType<typeof setInterval> | null = null;
  private connecting = false;
  private failedSessions = new Map<string, number>();
  private readonly intervalMs: number;
  private readonly downstream: DownstreamManager;
  private readonly onConnected: () => Promise<void>;

  constructor(options: SessionPollerOptions) {
    this.downstream = options.downstream;
    this.intervalMs = options.intervalMs ?? 3_000;
    this.onConnected = options.onConnected;
  }

  start(): void {
    if (this.timer) return;
    log("info", `Session poller started (every ${this.intervalMs}ms)`);
    this.timer = setInterval(() => void this.poll(), this.intervalMs);
    void this.poll();
  }

  stop(): void {
    if (!this.timer) return;
    clearInterval(this.timer);
    this.timer = null;
    log("info", "Session poller stopped");
  }

  ensure(): void {
    if (!this.downstream.isConnected() && !this.timer) {
      this.start();
    }
  }

  private async poll(): Promise<void> {
    if (this.downstream.isConnected() || this.connecting) return;

    const sessions = loadSessions();
    if (sessions.length === 0) return;

    const sorted = sortSessionsByLastSeen(sessions);
    const now = Date.now();
    let candidates = sorted.filter((session) => {
      const failedAt = this.failedSessions.get(session.id);
      return failedAt === undefined || now - failedAt >= SessionPoller.BACKOFF_MS;
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
      log("warn", `Auto-connect to ${target.id} failed (backoff ${SessionPoller.BACKOFF_MS}ms), will try next session`, error);
    } finally {
      this.connecting = false;
    }
  }
}
