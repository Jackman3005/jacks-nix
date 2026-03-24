import { join } from "node:path";
import { mkdirSync, appendFile } from "./fs.js";
import { $ } from "bun";

const LOG_DIR = "/tmp/jacks-nix";
const ONE_HOUR_MS = 60 * 60 * 1000;

export interface SpawnResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

export interface StreamCallbacks {
  onStdout?: (line: string) => void;
  onStderr?: (line: string) => void;
}

/** Initialize the log directory and write the header. Returns the log file path. */
export async function initLogFile(name: string): Promise<string> {
  mkdirSync(LOG_DIR);
  const logPath = join(LOG_DIR, `${name}.log`);
  await Bun.write(logPath, `--- ${name} started: ${new Date().toISOString()} ---\n`);
  return logPath;
}

/** Append a line to the log file. Efficient — uses appendFileSync, no read-rewrite. */
export function appendLog(logPath: string, line: string): void {
  appendFile(logPath, line + "\n");
}

/** Get the last N lines from the log file. */
export async function getLastLogLines(logPath: string, n: number = 20): Promise<string[]> {
  const file = Bun.file(logPath);
  if (!(await file.exists())) return [];
  const content = await file.text();
  return content.split("\n").filter(Boolean).slice(-n);
}

/** Run a command and capture all output. Does not stream. */
export async function run(
  cmd: string[],
  options: {
    cwd?: string;
    env?: Record<string, string>;
    stdin?: "inherit" | "pipe" | "ignore";
    timeout?: number;
    logPath?: string;
  } = {},
): Promise<SpawnResult> {
  const timeout = options.timeout ?? ONE_HOUR_MS;

  const proc = Bun.spawn(cmd, {
    cwd: options.cwd,
    env: { ...process.env, ...options.env },
    stdin: options.stdin ?? "ignore",
    stdout: "pipe",
    stderr: "pipe",
  });

  const timer = setTimeout(() => proc.kill("SIGTERM"), timeout);

  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);

  const exitCode = await proc.exited;
  clearTimeout(timer);

  if (options.logPath) {
    appendLog(options.logPath, `$ ${cmd.join(" ")}`);
    if (stdout) appendLog(options.logPath, stdout);
    if (stderr) appendLog(options.logPath, stderr);
    appendLog(options.logPath, `exit: ${exitCode}`);
  }

  return { exitCode, stdout, stderr };
}

/** Run a command via bash (for sourcing nix profile, pipes, etc.). */
export async function runBash(
  script: string,
  options: {
    cwd?: string;
    env?: Record<string, string>;
    stdin?: "inherit" | "pipe" | "ignore";
    timeout?: number;
    logPath?: string;
  } = {},
): Promise<SpawnResult> {
  return run(["bash", "-c", script], options);
}

/** Run a command and stream output line by line. Returns exit code. */
export async function runStreaming(
  cmd: string[],
  callbacks: StreamCallbacks,
  options: {
    cwd?: string;
    env?: Record<string, string>;
    stdin?: "inherit" | "pipe" | "ignore";
    timeout?: number;
    logPath?: string;
  } = {},
): Promise<number> {
  const timeout = options.timeout ?? ONE_HOUR_MS;

  const proc = Bun.spawn(cmd, {
    cwd: options.cwd,
    env: { ...process.env, ...options.env },
    stdin: options.stdin ?? "ignore",
    stdout: "pipe",
    stderr: "pipe",
  });

  const timer = setTimeout(() => proc.kill("SIGTERM"), timeout);

  const streamLines = async (
    stream: ReadableStream<Uint8Array> | null,
    callback?: (line: string) => void,
    logPath?: string,
  ) => {
    if (!stream) return;
    if (!callback && !logPath) {
      await new Response(stream).text(); // drain
      return;
    }

    const reader = stream.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() || "";
      for (const line of lines) {
        if (line) {
          callback?.(line);
          if (logPath) appendLog(logPath, line);
        }
      }
    }
    if (buffer) {
      callback?.(buffer);
      if (logPath) appendLog(logPath, buffer);
    }
  };

  await Promise.all([
    streamLines(proc.stdout, callbacks.onStdout, options.logPath),
    streamLines(proc.stderr, callbacks.onStderr, options.logPath),
  ]);

  const exitCode = await proc.exited;
  clearTimeout(timer);

  if (options.logPath) {
    appendLog(options.logPath, `$ ${cmd.join(" ")} → exit ${exitCode}`);
  }

  return exitCode;
}

/** Run a bash command with streaming. */
export async function runBashStreaming(
  script: string,
  callbacks: StreamCallbacks,
  options: {
    cwd?: string;
    env?: Record<string, string>;
    stdin?: "inherit" | "pipe" | "ignore";
    timeout?: number;
    logPath?: string;
  } = {},
): Promise<number> {
  return runStreaming(["bash", "-c", script], callbacks, options);
}

// --- Nix output parsing ---

export const NIX_PHASES = [
  { name: "Evaluating configuration", pattern: /^evaluating|^trace:/ },
  { name: "Downloading packages", pattern: /^copying path/ },
  { name: "Building derivations", pattern: /^building '/ },
  { name: "Setting up groups", pattern: /^setting up groups/ },
  { name: "Setting up users", pattern: /^setting up users/ },
  { name: "Setting up applications", pattern: /^setting up \/Applications/ },
  { name: "Setting up /etc", pattern: /^setting up \/etc/ },
  { name: "Configuring services", pattern: /^setting up launchd|reloading/ },
  { name: "Configuring networking", pattern: /^configuring networking/ },
  { name: "Homebrew bundle", pattern: /^Homebrew bundle|brew bundle/ },
  { name: "Activating home-manager", pattern: /^Activating|^Starting Home Manager/ },
  { name: "Setting up fonts", pattern: /^setting up.*Fonts/ },
] as const;

/** Detect which nix phase a line belongs to. */
export function detectNixPhase(line: string): string | null {
  for (const phase of NIX_PHASES) {
    if (phase.pattern.test(line)) return phase.name;
  }
  return null;
}

/** Extract a human-readable detail from a nix output line. */
export function extractNixDetail(line: string): string | null {
  const copyMatch = line.match(/copying path '.*?\/[a-z0-9]+-(.+?)'/);
  if (copyMatch) return copyMatch[1];
  const buildMatch = line.match(/building '.*?\/[a-z0-9]+-(.+?)\.drv/);
  if (buildMatch) return buildMatch[1];
  return null;
}
