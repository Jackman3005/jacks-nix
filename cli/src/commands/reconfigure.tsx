import React, { useState, useEffect } from "react";
import { Box, Text, useApp } from "ink";
import Spinner from "ink-spinner";
import { Header } from "../components/Header.js";
import { ConfigForm } from "../components/ConfigForm.js";
import { ConfigSummary, ConfigDiff } from "../components/ConfigSummary.js";
import { Confirm } from "../components/Confirm.js";
import { PasswordInput } from "../components/PasswordInput.js";
import { StepProgress, type Step } from "../components/StepProgress.js";
import {
  loadSchema, loadDefaults, loadConfig, saveConfig, mergeConfig,
  exportConfigToEnv, buildEnvArgs, type ConfigValues, type Schema,
} from "../lib/config.js";
import { isSudoCached, cacheSudoWithPassword, startSudoRefresh } from "../lib/sudo.js";
import { buildUpdateSwitchCommand, runNixSwitch } from "../lib/nix.js";
import { darwinPreflight } from "../lib/darwin.js";
import { getPlatform } from "../lib/platform.js";
import { initLogFile, getLastLogLines, detectNixPhase, extractNixDetail } from "../lib/subprocess.js";

interface ReconfigureCommandProps {
  repoPath: string;
  nonInteractive?: boolean;
  verbose?: boolean;
}

type Phase =
  | "loading"
  | "form"
  | "diff"
  | "sudo"
  | "switching"
  | "done"
  | "error";

export function ReconfigureCommand({ repoPath, nonInteractive, verbose }: ReconfigureCommandProps) {
  const { exit } = useApp();
  const [phase, setPhase] = useState<Phase>("loading");
  const [oldValues, setOldValues] = useState<ConfigValues>({});
  const [newValues, setNewValues] = useState<ConfigValues>({});
  const [schema, setSchema] = useState<Schema | null>(null);
  const [defaults, setDefaults] = useState<Record<string, unknown>>({});
  const [sources, setSources] = useState<Record<string, "env" | "saved" | "default">>({});
  const [steps, setSteps] = useState<Step[]>([]);
  const [logPath, setLogPath] = useState("");
  const [error, setError] = useState("");
  const [sudoError, setSudoError] = useState("");

  // Load config
  useEffect(() => {
    (async () => {
      try {
        const [s, d, saved] = await Promise.all([
          loadSchema(repoPath),
          loadDefaults(repoPath),
          loadConfig(repoPath),
        ]);
        const { values, sources: src } = mergeConfig(s, d, saved);
        setSchema(s);
        setDefaults(d);
        setOldValues(values);
        setNewValues(values);
        setSources(src);

        if (nonInteractive) {
          // Non-interactive: just re-apply current config
          await doSwitch(values, s);
        } else {
          setPhase("form");
        }
      } catch (e) {
        setError(String(e));
        setPhase("error");
      }
    })();
  }, []);

  const doSwitch = async (values: ConfigValues, s = schema) => {
    try {
      exportConfigToEnv(values);
      const log = await initLogFile("reconfigure");
      setLogPath(log);

      // Sudo
      const isDarwin = getPlatform() === "darwin";
      if (isDarwin && !(await isSudoCached())) {
        setPhase("sudo");
        return; // PasswordInput will call onSudoReady
      }

      await runSwitch(values, log, s);
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
    await runSwitch(newValues, logPath || await initLogFile("reconfigure"), schema);
  };

  const runSwitch = async (values: ConfigValues, log: string, s = schema) => {
    setPhase("switching");
    const stopRefresh = startSudoRefresh();

    const switchSteps: Step[] = [];
    if (getPlatform() === "darwin") {
      switchSteps.push({ name: "darwin_preflight", status: "pending" });
    }
    switchSteps.push({ name: "Building configuration", status: "pending" });
    setSteps(switchSteps);

    try {
      // darwin_preflight
      if (getPlatform() === "darwin") {
        updateStep(switchSteps, 0, "active");
        setSteps([...switchSteps]);
        await darwinPreflight(log);
        updateStep(switchSteps, 0, "done");
        setSteps([...switchSteps]);
      }

      // Nix switch
      const nixStepIdx = getPlatform() === "darwin" ? 1 : 0;
      updateStep(switchSteps, nixStepIdx, "active");
      setSteps([...switchSteps]);

      const switchCmd = buildUpdateSwitchCommand(repoPath, values);
      const exitCode = await runNixSwitch(switchCmd, {
        onStderr: (line) => {
          const phase = detectNixPhase(line);
          const detail = extractNixDetail(line);
          if (phase) {
            updateStep(switchSteps, nixStepIdx, "active", phase);
            setSteps([...switchSteps]);
          } else if (detail) {
            updateStep(switchSteps, nixStepIdx, "active", undefined, detail);
            setSteps([...switchSteps]);
          }
        },
      }, log);

      stopRefresh();

      if (exitCode !== 0) {
        updateStep(switchSteps, nixStepIdx, "failed");
        setSteps([...switchSteps]);
        const lastLines = await getLastLogLines(log, 20);
        setError(`Nix switch failed (exit ${exitCode}).\n\n${lastLines.join("\n")}\n\nFull log: ${log}`);
        setPhase("error");
        return;
      }

      updateStep(switchSteps, nixStepIdx, "done", "Configuration applied");
      setSteps([...switchSteps]);

      // Save config after success
      if (s) await saveConfig(repoPath, values, s);
      setPhase("done");
    } catch (e) {
      stopRefresh();
      setError(String(e));
      setPhase("error");
    }
  };

  // Render
  if (phase === "loading") {
    return <Text>  <Spinner type="dots" /> Loading configuration...</Text>;
  }

  if (phase === "error") {
    return (
      <Box flexDirection="column">
        <Text color="red">  Error: {error}</Text>
        {logPath && <Text dimColor>  Logs: {logPath}</Text>}
      </Box>
    );
  }

  return (
    <Box flexDirection="column">
      <Header icon="⚙️" title="jacks-nix reconfigure" />

      {phase === "form" && schema && (
        <ConfigForm
          schema={schema}
          currentValues={oldValues}
          sources={sources}
          mode="reconfigure"
          onSubmit={(vals) => {
            setNewValues(vals);
            setPhase("diff");
          }}
        />
      )}

      {phase === "diff" && schema && (
        <Box flexDirection="column">
          <ConfigDiff schema={schema} oldValues={oldValues} newValues={newValues} />
          <Confirm
            message="Press Enter to apply (Ctrl+C to cancel)..."
            onConfirm={() => doSwitch(newValues)}
          />
        </Box>
      )}

      {phase === "sudo" && (
        <PasswordInput onSubmit={onSudoReady} error={sudoError} />
      )}

      {phase === "switching" && <StepProgress steps={steps} />}

      {phase === "done" && (
        <Box flexDirection="column" marginTop={1}>
          <Text color="green">  ✅ Configuration applied</Text>
          {logPath && <Text dimColor>     Logs: {logPath}</Text>}
          <Text dimColor>     Run: exec zsh</Text>
        </Box>
      )}
    </Box>
  );
}

function updateStep(steps: Step[], index: number, status: Step["status"], name?: string, detail?: string) {
  if (index < steps.length) {
    steps[index] = {
      ...steps[index],
      status,
      ...(name ? { name } : {}),
      ...(detail !== undefined ? { detail } : {}),
    };
  }
}
