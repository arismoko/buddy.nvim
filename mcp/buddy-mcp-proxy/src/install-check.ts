import * as fs from "node:fs";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { log } from "./logger.js";
import { getSessionsPath } from "./sessions.js";

const execFileAsync = promisify(execFile);

type InstallStatus = "installed" | "missing" | "check_failed";

let buddyInstallStatus: InstallStatus | null = null;
let buddyInstallCheckPromise: Promise<InstallStatus> | null = null;

export async function checkBuddyInstalled(): Promise<InstallStatus> {
  if (buddyInstallStatus !== null) {
    return buddyInstallStatus;
  }

  if (!buddyInstallCheckPromise) {
    buddyInstallCheckPromise = (async (): Promise<InstallStatus> => {
      try {
        const { stdout } = await execFileAsync(
          "nvim",
          [
            "--headless",
            "-c",
            "lua local ok,_=pcall(require,'buddy'); print(ok and 'BUDDY_OK' or 'BUDDY_MISSING')",
            "-c",
            "qa!",
          ],
          { timeout: 10_000 },
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

export async function getNoSessionsHint(): Promise<string> {
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
  lines.push(fs.existsSync(sessionsPath) ? "  - File exists" : "  - File does not exist yet");
  return lines.join("\n");
}
