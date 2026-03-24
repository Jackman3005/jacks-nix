import { join } from "node:path";
import { run, runBash } from "./subprocess.js";
import { isSymlink, pathExists, rm } from "./fs.js";

/** darwin_preflight: resolve macOS issues that prevent darwin-rebuild. */
export async function darwinPreflight(logPath: string): Promise<string[]> {
  const actions: string[] = [];

  const etcFiles = ["/etc/bashrc", "/etc/zshrc", "/etc/zshenv", "/etc/zprofile", "/etc/nix/nix.conf"];
  for (const f of etcFiles) {
    if (pathExists(f) && !isSymlink(f)) {
      const result = await run(["sudo", "mv", f, `${f}.before-nix-darwin`], { logPath });
      if (result.exitCode === 0) actions.push(`Moved ${f} → ${f}.before-nix-darwin`);
    }
  }

  const hmApps = join(process.env.HOME || "/Users/unknown", "Applications", "Home Manager Apps");
  if (isSymlink(hmApps)) {
    await rm(hmApps);
    actions.push("Removed old Home Manager Apps symlink");
  }

  return actions;
}

/** Check if Xcode CLT is installed. */
export async function isXcodeCltInstalled(): Promise<boolean> {
  return (await run(["xcode-select", "-p"])).exitCode === 0;
}

/** Trigger Xcode CLT install and poll until complete. */
export async function installXcodeClt(
  onProgress?: (message: string) => void,
  timeout = 600_000,
): Promise<boolean> {
  await run(["xcode-select", "--install"]);
  onProgress?.("Waiting for Xcode Command Line Tools installation...");

  const start = Date.now();
  while (Date.now() - start < timeout) {
    await Bun.sleep(5000);
    if ((await run(["xcode-select", "-p"])).exitCode === 0) return true;
    onProgress?.("Still waiting for Xcode Command Line Tools...");
  }
  return false;
}

/** Rollback nix-darwin to previous generation. */
export async function rollbackDarwin(logPath: string): Promise<number> {
  return (await run(["sudo", "darwin-rebuild", "--rollback"], { logPath })).exitCode;
}

/** Restore /etc files from .before-nix-darwin backups. */
export async function restoreEtcFiles(logPath: string): Promise<string[]> {
  const restored: string[] = [];
  for (const f of ["/etc/bashrc", "/etc/zshrc", "/etc/zshenv", "/etc/zprofile", "/etc/nix/nix.conf"]) {
    const backup = `${f}.before-nix-darwin`;
    if (pathExists(backup)) {
      if (pathExists(f)) await run(["sudo", "rm", "-f", f], { logPath });
      await run(["sudo", "mv", backup, f], { logPath });
      restored.push(f);
    }
  }
  return restored;
}

/** Full Nix uninstall on macOS. */
export async function uninstallNixMacOS(
  logPath: string,
  onStep?: (step: string) => void,
): Promise<void> {
  onStep?.("Stopping Nix daemon...");
  await run(["sudo", "launchctl", "bootout", "system/org.nixos.nix-daemon"], { logPath });
  for (const plist of [
    "/Library/LaunchDaemons/org.nixos.nix-daemon.plist",
    "/Library/LaunchDaemons/org.nixos.darwin-store.plist",
    "/Library/LaunchDaemons/org.nixos.activate-system.plist",
  ]) {
    if (pathExists(plist)) await run(["sudo", "rm", "-f", plist], { logPath });
  }

  onStep?.("Removing build users...");
  for (let i = 1; i <= 32; i++) {
    await run(["sudo", "dscl", ".", "-delete", `/Users/nixbld${i}`], { logPath });
  }
  await run(["sudo", "dscl", ".", "-delete", "/Groups/nixbld"], { logPath });

  onStep?.("Removing Nix store volume...");
  await run(["sudo", "diskutil", "apfs", "deleteVolume", "/nix"], { logPath });

  onStep?.("Cleaning system configuration...");
  await runBash("sudo sed -i '' '/^nix$/d' /etc/synthetic.conf 2>/dev/null || true", { logPath });
  await runBash("sudo sed -i '' '/\\/nix/d' /etc/fstab 2>/dev/null || true", { logPath });

  if (pathExists("/nix")) await run(["sudo", "rm", "-rf", "/nix"], { logPath });

  onStep?.("Cleaning up...");
  const home = process.env.HOME || "/Users/unknown";
  for (const conf of [`${home}/.bash_profile`, `${home}/.bashrc`, `${home}/.zshrc`, `${home}/.profile`]) {
    if (pathExists(conf)) {
      await runBash(`sed -i '' '/nix-daemon\\|nix-profile\\|\\.nix-/d' "${conf}" 2>/dev/null || true`, { logPath });
    }
  }
}
