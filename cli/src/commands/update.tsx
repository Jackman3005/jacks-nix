import React, { useState, useEffect } from "react";
import { Box, Text, useApp } from "ink";
import Spinner from "ink-spinner";
import { Header } from "../components/Header.js";
import { ChangelogView } from "../components/ChangelogView.js";
import { ConfigForm } from "../components/ConfigForm.js";
import { Confirm } from "../components/Confirm.js";
import { PasswordInput } from "../components/PasswordInput.js";
import { ProgressBar } from "../components/ProgressBar.js";
import { StepProgress, type Step } from "../components/StepProgress.js";
import {
  loadSchema, loadDefaults, loadConfig, saveConfig, mergeConfig,
  exportConfigToEnv, findNewEntries, recordAppliedVersion, hasConfig,
  getAppliedVersion, type ConfigValues, type Schema,
} from "../lib/config.js";
import {
  fetchLatestTag, checkoutLatest, getVersion, getRemoteVersion,
  getHead, getLatestTagHash, isDirty, getFileFromTag,
} from "../lib/git.js";
import { aggregateChangelogs } from "../lib/changelog.js";
import { getDeclaredPackages, clearPackagesCache } from "../lib/packages.js";
import { isSudoCached, cacheSudoWithPassword, startSudoRefresh } from "../lib/sudo.js";
import { buildUpdateSwitchCommand, runNixSwitch, runGarbageCollection } from "../lib/nix.js";
import { darwinPreflight } from "../lib/darwin.js";
import { getPlatform, getExpectedCliVersion, CLI_VERSION, getBinaryDownloadUrl, getArch, downloadBinary, getLocalBinaryPath } from "../lib/platform.js";
import { initLogFile, getLastLogLines, detectNixPhase, extractNixDetail } from "../lib/subprocess.js";

interface UpdateCommandProps {
  repoPath: string;
  nonInteractive?: boolean;
  verbose?: boolean;
}

type Phase =
  | "checking"
  | "upToDate"
  | "changelog"
  | "configPrompt"
  | "confirm"
  | "sudo"
  | "switching"
  | "done"
  | "error";

export function UpdateCommand({ repoPath, nonInteractive, verbose }: UpdateCommandProps) {
  const { exit } = useApp();
  const [phase, setPhase] = useState<Phase>("checking");
  const [localVersion, setLocalVersion] = useState("");
  const [remoteVersion, setRemoteVersion] = useState("");
  const [changelogData, setChangelogData] = useState<Awaited<ReturnType<typeof aggregateChangelogs>> | null>(null);
  const [declaredPackages, setDeclaredPackages] = useState<Set<string>>(new Set());
  const [schema, setSchema] = useState<Schema | null>(null);
  const [defaults, setDefaults] = useState<Record<string, unknown>>({});
  const [configValues, setConfigValues] = useState<ConfigValues>({});
  const [sources, setSources] = useState<Record<string, "env" | "saved" | "default">>({});
  const [newEntries, setNewEntries] = useState<any[]>([]);
  const [steps, setSteps] = useState<Step[]>([]);
  const [logPath, setLogPath] = useState("");
  const [error, setError] = useState("");
  const [sudoError, setSudoError] = useState("");
  const [downloadProgress, setDownloadProgress] = useState<{ current: number; total: number } | null>(null);
  const [dirtyWarning, setDirtyWarning] = useState(false);

  // Phase 1: Check for updates
  useEffect(() => {
    (async () => {
      try {
        // Check for uncommitted changes
        if (await isDirty(repoPath)) {
          if (nonInteractive) {
            setError("Repository has uncommitted changes. Please stash or commit first.");
            setPhase("error");
            return;
          }
          setDirtyWarning(true);
        }

        const log = await initLogFile("update");
        setLogPath(log);

        // Fetch latest
        await fetchLatestTag(repoPath, log);

        const [localHead, latestHash, localVer, remoteVer] = await Promise.all([
          getHead(repoPath),
          getLatestTagHash(repoPath),
          getVersion(repoPath),
          getRemoteVersion(repoPath),
        ]);

        setLocalVersion(localVer);
        setRemoteVersion(remoteVer);

        const appliedVer = await getAppliedVersion(repoPath);

        // Up to date if: same commit OR (same version AND already applied)
        if (localHead === latestHash || (localVer === remoteVer && appliedVer === localVer)) {
          setPhase("upToDate");
          return;
        }

        // Load changelog
        const [clData, packages] = await Promise.all([
          aggregateChangelogs(repoPath, parseInt(localVer), parseInt(remoteVer), { fromTag: true }),
          getDeclaredPackages(repoPath).catch(() => []),
        ]);
        setChangelogData(clData);
        setDeclaredPackages(new Set(packages));

        // Check for new config keys from remote schema
        const remoteSchemaStr = await getFileFromTag(repoPath, "tags/latest", "config/schema.json");
        const currentSaved = await loadConfig(repoPath);
        const currentDefaults = await loadDefaults(repoPath);

        if (remoteSchemaStr) {
          const remoteSchema: Schema = JSON.parse(remoteSchemaStr);
          setSchema(remoteSchema);
          setDefaults(currentDefaults);
          const { values, sources: src } = mergeConfig(remoteSchema, currentDefaults, currentSaved);
          setConfigValues(values);
          setSources(src);
          const newKeys = findNewEntries(remoteSchema, currentSaved);
          setNewEntries(newKeys);

          if (newKeys.length > 0 && !nonInteractive) {
            setPhase("changelog"); // Show changelog first, then config prompt
            return;
          }
        } else {
          // No remote schema — load local
          const s = await loadSchema(repoPath);
          setSchema(s);
          const { values, sources: src } = mergeConfig(s, currentDefaults, currentSaved);
          setConfigValues(values);
          setSources(src);
        }

        if (nonInteractive) {
          // Pass values directly — state hasn't re-rendered yet
          const merged = mergeConfig(
            remoteSchemaStr ? JSON.parse(remoteSchemaStr) : await loadSchema(repoPath),
            currentDefaults,
            currentSaved,
          );
          await doUpdate(merged.values);
        } else {
          setPhase("changelog");
        }
      } catch (e) {
        setError(String(e));
        setPhase("error");
      }
    })();
  }, []);

  const doUpdate = async (values = configValues) => {
    try {
      exportConfigToEnv(values);
      setConfigValues(values);

      const isDarwin = getPlatform() === "darwin";
      if (isDarwin && !(await isSudoCached())) {
        if (nonInteractive) {
          // Try non-interactive sudo
          const proc = Bun.spawn(["sudo", "-v"], { stdin: "inherit" });
          await proc.exited;
        } else {
          setPhase("sudo");
          return;
        }
      }

      await runUpdate(values);
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
    await runUpdate(configValues);
  };

  const runUpdate = async (values: ConfigValues) => {
    setPhase("switching");
    const log = logPath || await initLogFile("update");
    const stopRefresh = startSudoRefresh();
    const isDarwin = getPlatform() === "darwin";

    const allSteps: Step[] = [
      { name: "Checking out latest", status: "pending" },
      { name: "Updating CLI binary", status: "pending" },
      { name: "Cleaning old generations", status: "pending" },
      ...(isDarwin ? [{ name: "darwin_preflight", status: "pending" as const }] : []),
      { name: "Building configuration", status: "pending" },
    ];
    setSteps(allSteps);

    try {
      let stepIdx = 0;

      // 1. Checkout
      activate(allSteps, stepIdx);
      setSteps([...allSteps]);
      const checkoutResult = await checkoutLatest(repoPath, log);
      if (checkoutResult !== 0) throw new Error("git checkout failed");
      complete(allSteps, stepIdx++);
      setSteps([...allSteps]);

      // Reload schema + defaults from disk (files changed after checkout)
      const freshSchema = await loadSchema(repoPath);
      const freshDefaults = await loadDefaults(repoPath);
      setSchema(freshSchema);
      setDefaults(freshDefaults);

      // 2. CLI binary update check
      activate(allSteps, stepIdx);
      setSteps([...allSteps]);
      const expectedVer = await getExpectedCliVersion(repoPath);
      if (expectedVer !== CLI_VERSION && expectedVer !== "unknown") {
        allSteps[stepIdx].detail = `${CLI_VERSION} → ${expectedVer}`;
        setSteps([...allSteps]);
        try {
          const url = getBinaryDownloadUrl(getPlatform(), getArch());
          const tmpPath = getLocalBinaryPath() + ".tmp";
          await downloadBinary(url, tmpPath, (received, total) => {
            setDownloadProgress({ current: received, total });
          });
          // Atomic rename after successful download
          const { renameSync } = await import("node:fs");
          renameSync(tmpPath, getLocalBinaryPath());
          setDownloadProgress(null);
        } catch (e) {
          // Download failure is non-fatal
          allSteps[stepIdx].detail = "Download failed, using current binary";
          setSteps([...allSteps]);
        }
      } else {
        allSteps[stepIdx].detail = "Already current";
        setSteps([...allSteps]);
      }
      complete(allSteps, stepIdx++);
      setSteps([...allSteps]);

      // 3. Garbage collection
      activate(allSteps, stepIdx);
      setSteps([...allSteps]);
      const gc = await runGarbageCollection(log);
      allSteps[stepIdx].detail = gc.message;
      complete(allSteps, stepIdx++);
      setSteps([...allSteps]);

      // 4. darwin_preflight (macOS)
      if (isDarwin) {
        activate(allSteps, stepIdx);
        setSteps([...allSteps]);
        await darwinPreflight(log);
        complete(allSteps, stepIdx++);
        setSteps([...allSteps]);
      }

      // 5. Nix switch
      activate(allSteps, stepIdx);
      setSteps([...allSteps]);
      const switchCmd = buildUpdateSwitchCommand(repoPath, values);
      const exitCode = await runNixSwitch(switchCmd, {
        onStderr: (line) => {
          const nixPhase = detectNixPhase(line);
          const detail = extractNixDetail(line);
          if (nixPhase) {
            allSteps[stepIdx] = { ...allSteps[stepIdx], name: nixPhase, status: "active" };
            setSteps([...allSteps]);
          } else if (detail) {
            allSteps[stepIdx] = { ...allSteps[stepIdx], detail, status: "active" };
            setSteps([...allSteps]);
          }
        },
      }, log);

      stopRefresh();

      if (exitCode !== 0) {
        fail(allSteps, stepIdx);
        setSteps([...allSteps]);
        const lastLines = await getLastLogLines(log, 20);
        setError(`Nix switch failed (exit ${exitCode}).\n\n${lastLines.join("\n")}\n\nFull log: ${log}`);
        setPhase("error");
        return;
      }

      complete(allSteps, stepIdx, "Configuration applied");
      setSteps([...allSteps]);

      // Post-success
      await saveConfig(repoPath, values, freshSchema);
      await recordAppliedVersion(repoPath);
      await clearPackagesCache();

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
        <Header icon="🔄" title="jacks-nix update" />
        <Text color="red">  ❌ {error}</Text>
        {logPath && <Text dimColor>  Logs: {logPath}</Text>}
      </Box>
    );
  }

  return (
    <Box flexDirection="column">
      <Header icon="🔄" title="jacks-nix update" />

      {phase === "checking" && (
        <Text>  <Spinner type="dots" /> Checking for updates...</Text>
      )}

      {phase === "upToDate" && (
        <Text color="green">  ✅ Already up to date (v{localVersion})</Text>
      )}

      {phase === "changelog" && changelogData && (
        <Box flexDirection="column">
          <ChangelogView
            fromVersion={localVersion}
            toVersion={remoteVersion}
            upgrades={changelogData.upgrades}
            added={changelogData.added}
            removed={changelogData.removed}
            commits={changelogData.commits}
            latestSizes={changelogData.latestSizes}
            earliestSizes={changelogData.earliestSizes}
            declaredPackages={declaredPackages}
          />
          {newEntries.length > 0 ? (
            <Confirm
              message="New config options available. Press Enter to configure..."
              onConfirm={() => setPhase("configPrompt")}
            />
          ) : (
            <Confirm
              message="Press Enter to update (Ctrl+C to cancel)..."
              onConfirm={() => doUpdate()}
            />
          )}
        </Box>
      )}

      {phase === "configPrompt" && schema && (
        <ConfigForm
          schema={schema}
          currentValues={configValues}
          sources={sources}
          mode="update"
          newEntries={newEntries}
          onSubmit={(vals) => {
            setConfigValues(vals);
            doUpdate(vals);
          }}
        />
      )}

      {phase === "sudo" && (
        <PasswordInput onSubmit={onSudoReady} error={sudoError} />
      )}

      {phase === "switching" && (
        <Box flexDirection="column">
          <StepProgress steps={steps} />
          {downloadProgress && (
            <ProgressBar
              label="Downloading CLI..."
              current={downloadProgress.current}
              total={downloadProgress.total}
              showBytes
            />
          )}
        </Box>
      )}

      {phase === "done" && (
        <Box flexDirection="column" marginTop={1}>
          <Text color="green">  ✅ Updated to v{remoteVersion}</Text>
          {logPath && <Text dimColor>     Logs: {logPath}</Text>}
          <Text dimColor>     Run: exec zsh</Text>
        </Box>
      )}

      {dirtyWarning && phase === "changelog" && (
        <Box marginTop={1}>
          <Text color="yellow">  ⚠ Repository has uncommitted changes. They will be overwritten.</Text>
        </Box>
      )}
    </Box>
  );
}

/** Update-check subcommand: non-blocking, for shell startup. */
export async function updateCheck(repoPath: string): Promise<void> {
  const log = await initLogFile("update-check");
  await fetchLatestTag(repoPath, log);

  const [localHead, latestHash, localVer, remoteVer] = await Promise.all([
    getHead(repoPath),
    getLatestTagHash(repoPath),
    getVersion(repoPath),
    getRemoteVersion(repoPath),
  ]);

  if (localHead === latestHash) return;

  console.log(`\n  🔄 jacks-nix update available: v${localVer} → v${remoteVer}`);
  console.log(`     Run: jn update\n`);
}

// Helpers
function activate(steps: Step[], idx: number) { steps[idx] = { ...steps[idx], status: "active" }; }
function complete(steps: Step[], idx: number, detail?: string) { steps[idx] = { ...steps[idx], status: "done", ...(detail ? { detail } : {}) }; }
function fail(steps: Step[], idx: number) { steps[idx] = { ...steps[idx], status: "failed" }; }
