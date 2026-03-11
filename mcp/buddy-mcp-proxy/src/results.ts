import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";

export function textResult(text: string): CallToolResult {
  return { content: [{ type: "text", text }] };
}

export function textError(text: string): CallToolResult {
  return { content: [{ type: "text", text }], isError: true };
}
