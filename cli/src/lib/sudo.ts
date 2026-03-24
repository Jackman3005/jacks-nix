import { run } from "./subprocess.js";

/** Check if sudo credentials are already cached. */
export async function isSudoCached(): Promise<boolean> {
  const result = await run(["sudo", "-n", "true"]);
  return result.exitCode === 0;
}

/**
 * Validate a password and cache sudo credentials.
 * Two-step pattern: `sudo -S -v` reads password from stdin, caches creds.
 * Subsequent `sudo` calls use cached creds without -S (avoids sudo 1.9.9+ stdin bug).
 */
export async function cacheSudoWithPassword(password: string): Promise<boolean> {
  const proc = Bun.spawn(["sudo", "-S", "-v"], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });

  proc.stdin.write(password + "\n");
  proc.stdin.flush();
  proc.stdin.end();

  return (await proc.exited) === 0;
}

/** Acquire sudo in non-interactive mode (for CI with passwordless sudo). */
export async function acquireSudoNonInteractive(): Promise<boolean> {
  const result = await run(["sudo", "-v"], { stdin: "inherit" });
  return result.exitCode === 0;
}

/**
 * Keep sudo credentials fresh in the background.
 * Returns a cleanup function to stop the refresh loop.
 */
export function startSudoRefresh(): () => void {
  const interval = setInterval(async () => {
    try {
      await run(["sudo", "-n", "true"]);
    } catch {}
  }, 55_000); // Refresh every 55s (default sudo timeout is 5min)

  return () => clearInterval(interval);
}

/** Build a sudo command with optional env var passthrough. */
export function buildSudoCommand(cmd: string[], envArgs: string[] = []): string[] {
  if (envArgs.length > 0) {
    return ["sudo", "env", ...envArgs, ...cmd];
  }
  return ["sudo", ...cmd];
}
