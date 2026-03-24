import { run, runBash } from "./subprocess.js";
import { pathExists, rmrf } from "./fs.js";

/** Rollback home-manager to previous generation. */
export async function rollbackHomeManager(logPath: string): Promise<number> {
  return (await runBash("home-manager switch --rollback 2>&1 || home-manager generations | head -2", { logPath })).exitCode;
}

/** Full Nix uninstall on Linux. */
export async function uninstallNixLinux(
  logPath: string,
  onStep?: (step: string) => void,
): Promise<void> {
  onStep?.("Stopping Nix daemon...");
  await run(["sudo", "systemctl", "stop", "nix-daemon.service"], { logPath });
  await run(["sudo", "systemctl", "stop", "nix-daemon.socket"], { logPath });
  await run(["sudo", "systemctl", "disable", "nix-daemon.service"], { logPath });
  await run(["sudo", "systemctl", "disable", "nix-daemon.socket"], { logPath });

  for (const f of [
    "/etc/systemd/system/nix-daemon.service",
    "/etc/systemd/system/nix-daemon.socket",
    "/usr/lib/systemd/system/nix-daemon.service",
    "/usr/lib/systemd/system/nix-daemon.socket",
  ]) {
    if (pathExists(f)) await run(["sudo", "rm", "-f", f], { logPath });
  }
  await run(["sudo", "systemctl", "daemon-reload"], { logPath });

  onStep?.("Removing build users...");
  for (let i = 1; i <= 32; i++) {
    await run(["sudo", "userdel", `nixbld${i}`], { logPath });
  }
  await run(["sudo", "groupdel", "nixbld"], { logPath });

  onStep?.("Removing Nix store...");
  if (pathExists("/nix")) await run(["sudo", "rm", "-rf", "/nix"], { logPath });

  onStep?.("Cleaning up...");
  const home = process.env.HOME || "/root";
  for (const conf of [`${home}/.bash_profile`, `${home}/.bashrc`, `${home}/.zshrc`, `${home}/.profile`]) {
    if (pathExists(conf)) {
      await runBash(`sed -i '/nix-daemon\\|nix-profile\\|\\.nix-/d' "${conf}" 2>/dev/null || true`, { logPath });
    }
  }

  for (const p of [`${home}/.nix-profile`, `${home}/.nix-defexpr`, `${home}/.nix-channels`, `${home}/.local/state/nix`, `${home}/.cache/nix`]) {
    if (pathExists(p)) await rmrf(p);
  }
}
