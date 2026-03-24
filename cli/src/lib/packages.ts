import { join } from "node:path";
import { mkdirSync } from "./fs.js";
import { runBash } from "./subprocess.js";
import { getPlatform } from "./platform.js";

const CACHE_DIR = join(process.env.HOME || "/root", ".cache", "jacks-nix");
const CACHE_FILE = join(CACHE_DIR, "declared-packages.txt");
const CACHE_MAX_AGE_S = 86400; // 24h

/** Get declared packages (cached for 24h). */
export async function getDeclaredPackages(repoPath: string): Promise<string[]> {
  const cacheFile = Bun.file(CACHE_FILE);
  if (await cacheFile.exists()) {
    // Check age via stat
    const ageCheck = Bun.spawnSync(["bash", "-c",
      `test $(( $(date +%s) - $(stat -f %m "${CACHE_FILE}" 2>/dev/null || stat -c %Y "${CACHE_FILE}" 2>/dev/null || echo 0) )) -lt ${CACHE_MAX_AGE_S}`
    ]);
    if (ageCheck.exitCode === 0) {
      return (await cacheFile.text()).split("\n").filter(Boolean);
    }
  }

  const platform = getPlatform();
  const flakeAttr = platform === "darwin"
    ? `darwinConfigurations.mac-arm64.config.home-manager.users.$(whoami).home.packages`
    : `homeConfigurations.linux-x64.config.home.packages`;

  const result = await runBash(
    `nix eval --json ".#${flakeAttr}" 2>/dev/null | tr ',' '\\n' | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | grep -v '^\\(hm-\\|home-configuration\\|session-vars\\|jacks-nix-\\|man-db\\|nix-zsh\\)' | sort -u`,
    { cwd: repoPath },
  );

  if (result.exitCode !== 0) return [];

  const packages = result.stdout.trim().split("\n").filter(Boolean);
  mkdirSync(CACHE_DIR, { recursive: true });
  await Bun.write(CACHE_FILE, packages.join("\n") + "\n");

  return packages;
}

/** Clear the declared packages cache. */
export async function clearPackagesCache(): Promise<void> {
  const file = Bun.file(CACHE_FILE);
  if (await file.exists()) await Bun.file(CACHE_FILE).delete();
}
