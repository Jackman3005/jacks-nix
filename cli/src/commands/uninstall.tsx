import React, { useState } from "react";
import { Box, Text, useInput, useApp } from "ink";
import { Header } from "../components/Header.js";
import { Confirm } from "../components/Confirm.js";
import { PasswordInput } from "../components/PasswordInput.js";
import { StepProgress, type Step } from "../components/StepProgress.js";
import { getPlatform, getRepoPath } from "../lib/platform.js";
import { rollbackDarwin, restoreEtcFiles, uninstallNixMacOS } from "../lib/darwin.js";
import { rollbackHomeManager, uninstallNixLinux } from "../lib/linux.js";
import { isSudoCached, cacheSudoWithPassword, startSudoRefresh } from "../lib/sudo.js";
import { isNixInstalled } from "../lib/nix.js";
import { initLogFile, getLastLogLines } from "../lib/subprocess.js";
import { rmrf, pathExists } from "../lib/fs.js";

interface UninstallCommandProps {
  repoPath: string;
  nonInteractive?: boolean;
}

type Phase = "options" | "confirm" | "sudo" | "running" | "done" | "error";

export function UninstallCommand({ repoPath, nonInteractive }: UninstallCommandProps) {
  const { exit } = useApp();
  const [phase, setPhase] = useState<Phase>("options");
  const [removeRepo, setRemoveRepo] = useState(true);
  const [removeNix, setRemoveNix] = useState(false);
  const [cursor, setCursor] = useState(0); // 0=repo, 1=nix
  const [steps, setSteps] = useState<Step[]>([]);
  const [logPath, setLogPath] = useState("");
  const [error, setError] = useState("");
  const [sudoError, setSudoError] = useState("");

  useInput((input, key) => {
    if (phase !== "options") return;

    if (key.upArrow || key.downArrow) {
      setCursor((c) => (c === 0 ? 1 : 0));
    } else if (input === " ") {
      if (cursor === 0) setRemoveRepo((v) => !v);
      if (cursor === 1) setRemoveNix((v) => !v);
    } else if (key.return) {
      setPhase("confirm");
    }
  });

  const doUninstall = async () => {
    if (!(await isSudoCached())) {
      setPhase("sudo");
      return;
    }
    await runUninstall();
  };

  const onSudoReady = async (password: string) => {
    const ok = await cacheSudoWithPassword(password);
    if (!ok) { setSudoError("Wrong password. Try again."); return; }
    setSudoError("");
    await runUninstall();
  };

  const runUninstall = async () => {
    setPhase("running");
    const log = await initLogFile("uninstall");
    setLogPath(log);
    const stopRefresh = startSudoRefresh();
    const isDarwin = getPlatform() === "darwin";

    const allSteps: Step[] = [
      { name: "Remove jacks-nix configuration", status: "pending" },
      ...(removeRepo ? [{ name: "Remove repository", status: "pending" as const }] : []),
      ...(removeNix ? [{ name: "Uninstall Nix", status: "pending" as const }] : []),
    ];
    setSteps(allSteps);

    try {
      let stepIdx = 0;

      // 1. Remove config (required)
      allSteps[stepIdx].status = "active";
      setSteps([...allSteps]);

      if (isDarwin) {
        await rollbackDarwin(log);
        await restoreEtcFiles(log);
      } else {
        await rollbackHomeManager(log);
      }

      // Clean local state
      for (const f of ["local/config.json", "local/applied-version.txt", "local/jacks-nix"]) {
        const fullPath = `${repoPath}/${f}`;
        if (pathExists(fullPath)) {
          await Bun.file(fullPath).delete().catch(() => {});
        }
      }

      allSteps[stepIdx].status = "done";
      setSteps([...allSteps]);
      stepIdx++;

      // 2. Remove repo (optional)
      if (removeRepo) {
        allSteps[stepIdx].status = "active";
        setSteps([...allSteps]);
        await rmrf(repoPath);
        allSteps[stepIdx].status = "done";
        setSteps([...allSteps]);
        stepIdx++;
      }

      // 3. Uninstall Nix (optional)
      if (removeNix && isNixInstalled()) {
        allSteps[stepIdx].status = "active";
        setSteps([...allSteps]);

        const onStep = (step: string) => {
          allSteps[stepIdx].detail = step;
          setSteps([...allSteps]);
        };

        if (isDarwin) {
          await uninstallNixMacOS(log, onStep);
        } else {
          await uninstallNixLinux(log, onStep);
        }

        allSteps[stepIdx].status = "done";
        setSteps([...allSteps]);
      }

      stopRefresh();
      setPhase("done");
    } catch (e) {
      stopRefresh();
      setError(String(e));
      setPhase("error");
    }
  };

  if (phase === "error") {
    return (
      <Box flexDirection="column">
        <Header icon="🗑️" title="jacks-nix uninstall" />
        <Text color="red">  ❌ {error}</Text>
        {logPath && <Text dimColor>  Logs: {logPath}</Text>}
      </Box>
    );
  }

  return (
    <Box flexDirection="column">
      <Header icon="🗑️" title="jacks-nix uninstall" />

      {phase === "options" && (
        <Box flexDirection="column">
          <Text>  The following actions will be performed:</Text>
          <Box marginTop={1} marginLeft={2}>
            <Text color="cyan">◉ Remove jacks-nix configuration (required)</Text>
          </Box>
          <Box marginLeft={4}>
            <Text dimColor>Rollback to previous system generation</Text>
          </Box>

          <Box marginTop={1} marginLeft={2}>
            <Text bold={cursor === 0} color={cursor === 0 ? "cyan" : undefined}>
              {cursor === 0 ? "› " : "  "}{removeRepo ? "◉" : "○"} Remove repository ({repoPath})
            </Text>
          </Box>

          <Box marginLeft={2}>
            <Text bold={cursor === 1} color={cursor === 1 ? "cyan" : removeNix ? "red" : undefined}>
              {cursor === 1 ? "› " : "  "}{removeNix ? "◉" : "○"} Uninstall Nix from the system
            </Text>
          </Box>
          {removeNix && (
            <Box marginLeft={6}>
              <Text color="yellow">⚠ This cannot be undone</Text>
            </Box>
          )}

          <Box marginTop={1}>
            <Text dimColor>  (↑↓ navigate, space toggle, enter continue)</Text>
          </Box>
        </Box>
      )}

      {phase === "confirm" && (
        <Box flexDirection="column">
          <Text>  Will remove:</Text>
          <Text color="red">    • jacks-nix configuration</Text>
          {removeRepo && <Text color="red">    • Repository at {repoPath}</Text>}
          {removeNix && <Text color="red">    • Nix (daemon, store, build users)</Text>}
          <Confirm
            message="Press Enter to uninstall (Ctrl+C to cancel)..."
            onConfirm={doUninstall}
          />
        </Box>
      )}

      {phase === "sudo" && (
        <PasswordInput onSubmit={onSudoReady} error={sudoError} />
      )}

      {phase === "running" && <StepProgress steps={steps} />}

      {phase === "done" && (
        <Box flexDirection="column" marginTop={1}>
          <Text color="green">  ✅ Uninstall complete</Text>
          {logPath && <Text dimColor>     Logs: {logPath}</Text>}
          <Text dimColor>     Restart your shell to complete cleanup.</Text>
        </Box>
      )}
    </Box>
  );
}
