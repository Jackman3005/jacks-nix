import React, { useState, useEffect } from "react";
import { Box, Text, useApp } from "ink";
import { join } from "node:path";
import { mkdirSync } from "../lib/fs.js";
import { Header } from "../components/Header.js";
import { ConfigForm } from "../components/ConfigForm.js";
import { Confirm } from "../components/Confirm.js";
import { PasswordInput } from "../components/PasswordInput.js";
import { StepProgress, type Step } from "../components/StepProgress.js";
import {
  loadSchema, loadDefaults, loadConfig, saveConfig, mergeConfig,
  exportConfigToEnv, hasConfig, recordAppliedVersion,
  type ConfigValues, type Schema,
} from "../lib/config.js";
import { cloneRepo, configureRemotes, fetchLatestTag, checkoutLatest } from "../lib/git.js";
import {
  isNixInstalled, installNix, initNixProfile, ensureNixFlakes,
  buildFirstInstallSwitchCommand, buildUpdateSwitchCommand, runNixSwitch,
} from "../lib/nix.js";
import { darwinPreflight, isXcodeCltInstalled, installXcodeClt } from "../lib/darwin.js";
import { isSudoCached, cacheSudoWithPassword, startSudoRefresh } from "../lib/sudo.js";
import { getPlatform, getRepoPath, getLocalBinaryPath } from "../lib/platform.js";
import {
  initLogFile, getLastLogLines, detectNixPhase, extractNixDetail,
} from "../lib/subprocess.js";
import { existsSync } from "../lib/fs.js";

interface InstallCommandProps {
  repoPath: string;
  nonInteractive?: boolean;
  verbose?: boolean;
}

type Phase =
  | "prerequisites"
  | "config"
  | "sudo"
  | "switching"
  | "done"
  | "error";

export function InstallCommand({ repoPath, nonInteractive, verbose }: InstallCommandProps) {
  const { exit } = useApp();
  const [phase, setPhase] = useState<Phase>("prerequisites");
  const [schema, setSchema] = useState<Schema | null>(null);
  const [defaults, setDefaults] = useState<Record<string, unknown>>({});
  const [configValues, setConfigValues] = useState<ConfigValues>({});
  const [sources, setSources] = useState<Record<string, "env" | "saved" | "default">>({});
  const [steps, setSteps] = useState<Step[]>([]);
  const [logPath, setLogPath] = useState("");
  const [error, setError] = useState("");
  const [sudoError, setSudoError] = useState("");
  const [isFirstInstall, setIsFirstInstall] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const log = await initLogFile("install");
        setLogPath(log);
        const isDarwin = getPlatform() === "darwin";

        const prereqSteps: Step[] = [];
        if (isDarwin) prereqSteps.push({ name: "Xcode Command Line Tools", status: "pending" });
        prereqSteps.push({ name: "Git", status: "pending" });
        prereqSteps.push({ name: "Repository", status: "pending" });
        prereqSteps.push({ name: "Nix", status: "pending" });
        setSteps(prereqSteps);

        let stepIdx = 0;

        // 1. Xcode CLT (macOS)
        if (isDarwin) {
          activate(prereqSteps, stepIdx);
          setSteps([...prereqSteps]);
          if (await isXcodeCltInstalled()) {
            prereqSteps[stepIdx].detail = "Already installed";
          } else {
            const ok = await installXcodeClt(
              (msg) => { prereqSteps[stepIdx].detail = msg; setSteps([...prereqSteps]); },
            );
            if (!ok) throw new Error("Xcode CLT installation timed out");
          }
          complete(prereqSteps, stepIdx++);
          setSteps([...prereqSteps]);
        }

        // 2. Git check
        activate(prereqSteps, stepIdx);
        setSteps([...prereqSteps]);
        const git = Bun.which("git");
        prereqSteps[stepIdx].detail = git ? "Found" : "Will use Nix's git after install";
        complete(prereqSteps, stepIdx++);
        setSteps([...prereqSteps]);

        // 3. Repository
        activate(prereqSteps, stepIdx);
        setSteps([...prereqSteps]);
        const repoExists = existsSync(repoPath);
        const configRepoOverride = !!process.env.JACKS_NIX_CONFIG_REPO_PATH;

        if (configRepoOverride) {
          prereqSteps[stepIdx].detail = "Using existing (JACKS_NIX_CONFIG_REPO_PATH)";
        } else if (repoExists) {
          prereqSteps[stepIdx].detail = "Updating existing";
          await fetchLatestTag(repoPath, log);
          await checkoutLatest(repoPath, log);
        } else {
          prereqSteps[stepIdx].detail = "Cloning";
          const exitCode = await cloneRepo(repoPath, log);
          if (exitCode !== 0) throw new Error("Failed to clone repository");
        }

        if (!configRepoOverride && repoExists) {
          await configureRemotes(repoPath, log);
        }
        complete(prereqSteps, stepIdx++);
        setSteps([...prereqSteps]);

        // Ensure local/ directory exists for config and binary storage
        mkdirSync(join(repoPath, "local"), { recursive: true });

        // 4. Nix
        activate(prereqSteps, stepIdx);
        setSteps([...prereqSteps]);
        if (isNixInstalled()) {
          prereqSteps[stepIdx].detail = "Already installed";
        } else {
          const exitCode = await installNix({
            onStderr: (line) => {
              prereqSteps[stepIdx].detail = line.slice(0, 60);
              setSteps([...prereqSteps]);
            },
          }, log);
          if (exitCode !== 0) throw new Error("Nix installation failed. See log: " + log);
        }
        complete(prereqSteps, stepIdx++);
        setSteps([...prereqSteps]);

        // Post-nix setup
        await ensureNixFlakes(log);
        if (getPlatform() === "linux") {
          await initNixProfile(log);
        }

        // Load config
        const [s, d, saved] = await Promise.all([
          loadSchema(repoPath),
          loadDefaults(repoPath),
          loadConfig(repoPath),
        ]);
        setSchema(s);
        setDefaults(d);
        setIsFirstInstall(Object.keys(saved).length === 0);
        const { values, sources: src } = mergeConfig(s, d, saved);
        setConfigValues(values);
        setSources(src);

        if (nonInteractive) {
          await doSwitch(values, s, log);
        } else {
          setPhase("config");
        }
      } catch (e) {
        setError(String(e));
        setPhase("error");
      }
    })();
  }, []);

  const doSwitch = async (values: ConfigValues, s: Schema, log?: string) => {
    try {
      exportConfigToEnv(values);
      const switchLog = log || logPath;

      const isDarwin = getPlatform() === "darwin";
      if (isDarwin && !(await isSudoCached())) {
        if (nonInteractive) {
          Bun.spawnSync(["sudo", "-v"], { stdin: "inherit" });
        } else {
          setPhase("sudo");
          return;
        }
      }

      await runInstallSwitch(values, s, switchLog);
    } catch (e) {
      setError(String(e));
      setPhase("error");
    }
  };

  const onSudoReady = async (password: string) => {
    const ok = await cacheSudoWithPassword(password);
    if (!ok) {
      setSudoError("Wrong password. Try again.");
      return;
    }
    setSudoError("");
    await runInstallSwitch(configValues, schema!, logPath);
  };

  const runInstallSwitch = async (values: ConfigValues, s: Schema, log: string) => {
    setPhase("switching");
    const stopRefresh = startSudoRefresh();
    const isDarwin = getPlatform() === "darwin";

    const switchSteps: Step[] = [];
    if (isDarwin) switchSteps.push({ name: "Preparing macOS", status: "pending" });
    switchSteps.push({ name: "Building configuration", status: "pending" });
    setSteps(switchSteps);

    try {
      let stepIdx = 0;

      // darwin_preflight
      if (isDarwin) {
        activate(switchSteps, stepIdx);
        setSteps([...switchSteps]);
        await darwinPreflight(log);
        complete(switchSteps, stepIdx++);
        setSteps([...switchSteps]);
      }

      // Nix switch
      activate(switchSteps, stepIdx);
      setSteps([...switchSteps]);

      // Use first-install command if darwin-rebuild/home-manager not yet available
      const hasDarwinRebuild = existsSync("/nix/var/nix/profiles/system/sw/bin/darwin-rebuild");
      const switchCmd = (isDarwin && !hasDarwinRebuild) || !Bun.which("home-manager")
        ? buildFirstInstallSwitchCommand(repoPath, values)
        : buildUpdateSwitchCommand(repoPath, values);

      const exitCode = await runNixSwitch(switchCmd, {
        onStderr: (line) => {
          const nixPhase = detectNixPhase(line);
          const detail = extractNixDetail(line);
          if (nixPhase) {
            switchSteps[stepIdx] = { ...switchSteps[stepIdx], name: nixPhase, status: "active" };
            setSteps([...switchSteps]);
          } else if (detail) {
            switchSteps[stepIdx] = { ...switchSteps[stepIdx], detail, status: "active" };
            setSteps([...switchSteps]);
          }
        },
      }, log);

      stopRefresh();

      if (exitCode !== 0) {
        fail(switchSteps, stepIdx);
        setSteps([...switchSteps]);
        const lastLines = await getLastLogLines(log, 20);
        setError(`Configuration failed (exit ${exitCode}).\n\n${lastLines.join("\n")}\n\nFull log: ${log}`);
        setPhase("error");
        return;
      }

      complete(switchSteps, stepIdx, "Configuration applied");
      setSteps([...switchSteps]);

      // Post-success
      await saveConfig(repoPath, values, s);
      await recordAppliedVersion(repoPath);
      setPhase("done");
    } catch (e) {
      stopRefresh();
      setError(String(e));
      setPhase("error");
    }
  };

  // --- Render ---
  if (phase === "error") {
    return (
      <Box flexDirection="column">
        <Header icon="📦" title="jacks-nix install" />
        <Text color="red">  ❌ {error}</Text>
        {logPath && <Text dimColor>  Logs: {logPath}</Text>}
      </Box>
    );
  }

  return (
    <Box flexDirection="column">
      <Header icon="📦" title="jacks-nix install" />

      {phase === "prerequisites" && <StepProgress steps={steps} />}

      {phase === "config" && schema && (
        <ConfigForm
          schema={schema}
          currentValues={configValues}
          sources={sources}
          mode={isFirstInstall ? "install" : "update"}
          onSubmit={(vals) => {
            setConfigValues(vals);
            doSwitch(vals, schema!);
          }}
        />
      )}

      {phase === "sudo" && (
        <PasswordInput onSubmit={onSudoReady} error={sudoError} />
      )}

      {phase === "switching" && <StepProgress steps={steps} />}

      {phase === "done" && (
        <Box flexDirection="column" marginTop={1}>
          <Text color="green">  ✅ jacks-nix installed successfully</Text>
          {logPath && <Text dimColor>     Logs: {logPath}</Text>}
          <Text dimColor>     Run: exec zsh</Text>
        </Box>
      )}
    </Box>
  );
}

function activate(steps: Step[], idx: number) { steps[idx] = { ...steps[idx], status: "active" }; }
function complete(steps: Step[], idx: number, detail?: string) { steps[idx] = { ...steps[idx], status: "done", ...(detail ? { detail } : {}) }; }
function fail(steps: Step[], idx: number) { steps[idx] = { ...steps[idx], status: "failed" }; }
