export type LogLevel = "info" | "warn" | "error";

export function log(level: LogLevel, message: string, data?: unknown): void {
  const line = `[${new Date().toISOString()}] [${level.toUpperCase()}] ${message}`;
  if (data !== undefined) {
    console.error(line, data);
    return;
  }
  console.error(line);
}
