import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { SSEClientTransport } from "@modelcontextprotocol/sdk/client/sse.js";
import { ToolListChangedNotificationSchema, type CallToolResult, type Tool } from "@modelcontextprotocol/sdk/types.js";
import { log } from "./logger.js";
import { getSessionUrl } from "./sessions.js";
import { PROXY_NAME, PROXY_VERSION } from "./version.js";
import type { BuddySession } from "./types.js";

export class DownstreamManager {
  private client: Client | null = null;
  private transport: SSEClientTransport | null = null;
  private currentSession: BuddySession | null = null;
  private cachedTools: Tool[] = [];
  private onToolsChanged: (() => Promise<void>) | null = null;

  setOnToolsChanged(callback: () => Promise<void>): void {
    this.onToolsChanged = callback;
  }

  async connect(session: BuddySession): Promise<void> {
    await this.disconnect();
    const url = getSessionUrl(session);
    log("info", `Connecting to downstream: ${url}`);

    try {
      const transportOptions: { requestInit?: RequestInit } = {};
      if (session.auth_token) {
        transportOptions.requestInit = {
          headers: { Authorization: `Bearer ${session.auth_token}` },
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

  async disconnect(): Promise<void> {
    if (this.transport) {
      try {
        await this.transport.close();
      } catch {
        // ignore close errors
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
    } catch (error) {
      log("error", "Failed to fetch downstream tools", error);
      this.cachedTools = [];
    }
  }

  async callTool(name: string, args: Record<string, unknown>): Promise<CallToolResult> {
    if (!this.client) {
      throw new Error("No downstream session connected");
    }

    try {
      const result = await this.client.callTool({ name, arguments: args });
      if ("content" in result) {
        return result as CallToolResult;
      }
      if ("toolResult" in result) {
        const toolResult = result.toolResult;
        return {
          content: [{ type: "text", text: typeof toolResult === "string" ? toolResult : JSON.stringify(toolResult, null, 2) }],
        };
      }
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    } catch (error) {
      log("error", `Failed to call tool ${name}`, error);
      await this.checkHealth();
      throw error;
    }
  }

  async checkHealth(): Promise<boolean> {
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
