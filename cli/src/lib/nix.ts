import { join } from "node:path";
import { mkdirSync } from "./fs.js";
import { run, runBash, runBashStreaming, appendLog, type StreamCallbacks } from "./subprocess.js";
import { buildEnvArgs, type ConfigValues } from "./config.js";
import { getNixBinPath, getNixProfileScript, getPlatform } from "./platform.js";

/** Check if Nix is installed. */
export const isNixInstalled = (): boolean =>
  Bun.spawnSync(["test", "-f", "/nix/var/nix/profiles/default/bin/nix"]).exitCode === 0;

/** Install Nix via the official installer. It invokes sudo internally. */
export async function installNix(callbacks: StreamCallbacks, logPath: string): Promise<number> {
  return runBashStreaming(
    "curl -L https://nixos.org/nix/install | sh -s -- --daemon",
    callbacks,
    { logPath },
  );
}

/** Initialize nix profile (fixes home-manager bootstrap bug on fresh Linux installs). */
export async function initNixProfile(logPath: string): Promise<void> {
  const nixBin = getNixBinPath();
  await runBash(`source ${getNixProfileScript()} && ${nixBin} profile list`, { logPath });
}

/** Build nix switch command for first install (nix run nix-darwin/home-manager). */
export function buildFirstInstallSwitchCommand(repoPath: string, configValues: ConfigValues) {
  const nixBin = getNixBinPath();
  const profile = getNixProfileScript();
  const envArgs = buildEnvArgs(configValues);

  if (getPlatform() === "darwin") {
    return {
      cmd: `source ${profile} && ${nixBin} run --impure --extra-experimental-features nix-command --extra-experimental-features flakes nix-darwin -- switch --impure --flake "${repoPath}#mac-arm64"`,
      envArgs,
    };
  }
  return {
    cmd: `source ${profile} && ${nixBin} run --impure --extra-experimental-features nix-command --extra-experimental-features flakes home-manager -- switch --impure --flake "${repoPath}#linux-x64"`,
    envArgs: [] as string[],
  };
}

/** Build nix switch command for updates (darwin-rebuild/home-manager already in PATH). */
export function buildUpdateSwitchCommand(repoPath: string, configValues: ConfigValues) {
  const profile = getNixProfileScript();
  const envArgs = buildEnvArgs(configValues);

  if (getPlatform() === "darwin") {
    return {
      cmd: `source ${profile} && /nix/var/nix/profiles/system/sw/bin/darwin-rebuild switch --impure --flake "${repoPath}#mac-arm64"`,
      envArgs,
    };
  }
  return {
    cmd: `source ${profile} && home-manager switch --impure --flake "${repoPath}#linux-x64"`,
    envArgs: [] as string[],
  };
}

/** Run nix switch with streaming. Handles sudo + env on macOS. */
export async function runNixSwitch(
  switchCmd: { cmd: string; envArgs: string[] },
  callbacks: StreamCallbacks,
  logPath: string,
): Promise<number> {
  if (getPlatform() === "darwin") {
    const escapedCmd = switchCmd.cmd.replace(/'/g, "'\\''");
    const envPart = switchCmd.envArgs.length > 0
      ? `env ${switchCmd.envArgs.map((e) => `"${e}"`).join(" ")} `
      : "";
    return runBashStreaming(`sudo ${envPart}bash -c '${escapedCmd}'`, callbacks, { logPath });
  }
  return runBashStreaming(switchCmd.cmd, callbacks, { logPath });
}

/** Run garbage collection. macOS uses sudo, Linux doesn't. */
export async function runGarbageCollection(logPath: string) {
  const cmd = getPlatform() === "darwin"
    ? ["sudo", "nix-collect-garbage", "--delete-older-than", "30d"]
    : ["nix-collect-garbage", "--delete-older-than", "30d"];
  const result = await run(cmd, { logPath });
  return {
    exitCode: result.exitCode,
    message: result.exitCode === 0
      ? "Cleaned up old generations"
      : "Could not clean up old generations (this is usually fine)",
  };
}

/** Ensure nix experimental features are enabled in user config. */
export async function ensureNixFlakes(logPath: string): Promise<void> {
  const nixConfDir = join(process.env.HOME || "/root", ".config", "nix");
  const nixConfPath = join(nixConfDir, "nix.conf");
  const nixConf = Bun.file(nixConfPath);

  if (await nixConf.exists()) {
    if ((await nixConf.text()).includes("experimental-features")) return;
  }

  mkdirSync(nixConfDir, { recursive: true });
  const existing = (await nixConf.exists()) ? await nixConf.text() : "";
  await Bun.write(nixConfPath, existing + "\nexperimental-features = nix-command flakes\n");
  appendLog(logPath, "Added experimental-features to nix.conf");
}
