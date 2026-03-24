import { join } from "node:path";
import { mkdirSync } from "./fs.js";

export type Platform = "darwin" | "linux";
export type Arch = "arm64" | "x64";

export const getPlatform = (): Platform =>
  process.platform === "darwin" ? "darwin" : "linux";

export const getArch = (): Arch =>
  process.arch === "arm64" ? "arm64" : "x64";

/** Resolve the jacks-nix repo path. Env var > default. */
export const getRepoPath = (): string =>
  process.env.JACKS_NIX_CONFIG_REPO_PATH ||
  join(process.env.HOME || "/root", ".config", "jacks-nix");

/** Path to the CLI binary in the local directory. */
export const getLocalBinaryPath = (): string =>
  join(getRepoPath(), "local", "jacks-nix");

/** Full path to nix binary (uses Bun.which, falls back to default install path). */
export const getNixBinPath = (): string =>
  Bun.which("nix") ?? "/nix/var/nix/profiles/default/bin/nix";

/** Full path to git (uses Bun.which, falls back to nix profile git). */
export const getGitPath = (): string =>
  Bun.which("git") ?? "/nix/var/nix/profiles/default/bin/git";

/** Nix profile script for sourcing after fresh install. */
export const getNixProfileScript = (): string => {
  const daemon = "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh";
  const single = "/nix/var/nix/profiles/default/etc/profile.d/nix.sh";
  // Use Bun.file for async-capable existence check
  // But this runs at call time in sync context, so use spawnSync
  const check = Bun.spawnSync(["test", "-f", daemon]);
  return check.exitCode === 0 ? daemon : single;
};

/** Read expected CLI version from the repo's cli/package.json. */
export async function getExpectedCliVersion(repoPath: string): Promise<string> {
  const file = Bun.file(join(repoPath, "cli", "package.json"));
  if (!(await file.exists())) return "unknown";
  const pkg = await file.json();
  return pkg.version ?? "unknown";
}

/** Read config VERSION from the repo. */
export async function getConfigVersion(repoPath: string): Promise<string> {
  const file = Bun.file(join(repoPath, "VERSION"));
  return (await file.exists()) ? (await file.text()).trim() : "unknown";
}

/** The baked-in CLI version (read from package.json at build/dev time). */
export const CLI_VERSION: string = (() => {
  // Try multiple paths — import.meta.dir is virtual in compiled binaries
  const candidates = [
    join(import.meta.dir, "..", "..", "package.json"),           // dev mode
    join(process.cwd(), "cli", "package.json"),                  // run from repo root
    join(process.execPath, "..", "..", "cli", "package.json"),   // compiled binary in local/
  ];
  for (const pkgPath of candidates) {
    try {
      const result = Bun.spawnSync(["cat", pkgPath]);
      if (result.exitCode === 0) {
        const version = JSON.parse(result.stdout.toString()).version;
        if (version) return version;
      }
    } catch {}
  }
  return "dev";
})();

/** Whether running in a TTY. */
export const isInteractive = (): boolean =>
  process.stdout.isTTY === true && process.stdin.isTTY === true;

/** Binary download URL. */
export const getBinaryDownloadUrl = (platform: Platform, arch: Arch): string =>
  `https://github.com/Jackman3005/jacks-nix/releases/download/latest/jacks-nix-${platform}-${arch}`;

/** Download a file with progress tracking via fetch ReadableStream. */
export async function downloadWithProgress(
  url: string,
  onProgress?: (received: number, total: number) => void,
): Promise<Buffer> {
  const response = await fetch(url, { redirect: "follow" });
  if (!response.ok) throw new Error(`Download failed: ${response.status} ${response.statusText}`);

  const contentLength = parseInt(response.headers.get("content-length") || "0", 10);
  const reader = response.body?.getReader();
  if (!reader) throw new Error("No response body");

  const chunks: Uint8Array[] = [];
  let received = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    received += value.length;
    onProgress?.(received, contentLength);
  }

  return Buffer.concat(chunks);
}

/** Download binary and write as executable. */
export async function downloadBinary(
  url: string,
  destPath: string,
  onProgress?: (received: number, total: number) => void,
): Promise<void> {
  const data = await downloadWithProgress(url, onProgress);
  mkdirSync(join(destPath, ".."), { recursive: true });
  await Bun.write(destPath, data);
  // Make executable
  Bun.spawnSync(["chmod", "+x", destPath]);
}
