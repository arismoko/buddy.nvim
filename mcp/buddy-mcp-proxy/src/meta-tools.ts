import type { Tool } from "@modelcontextprotocol/sdk/types.js";

export const META_TOOLS: Tool[] = [
  {
    name: "buddy_sessions_list",
    description: "List all available buddy.nvim sessions from the sessions registry",
    inputSchema: { type: "object", properties: {}, required: [] },
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
        index: { type: "number", description: "1-based index (sorted by last_seen desc)" },
      },
      required: [],
    },
  },
  {
    name: "buddy_session_info",
    description: "Get information about the currently selected buddy.nvim session",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "buddy_refresh",
    description: "Refresh the sessions list and reconnect to the current session if still available",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
];
