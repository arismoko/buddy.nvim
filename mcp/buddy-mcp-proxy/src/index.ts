import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { DownstreamManager } from "./downstream.js";
import { registerHandlers } from "./handlers.js";
import { log } from "./logger.js";
import { SessionPoller } from "./poller.js";
import { PROXY_NAME, PROXY_VERSION } from "./version.js";

async function main() {
  log("info", `Starting ${PROXY_NAME}`);

  const downstream = new DownstreamManager();
  const server = new Server(
    { name: PROXY_NAME, version: PROXY_VERSION },
    { capabilities: { tools: { listChanged: true } } },
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
    onConnected: notifyToolsChanged,
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
