import React from "react";
import { Box, Text, Static } from "ink";
import Spinner from "ink-spinner";

export interface Step {
  name: string;
  status: "pending" | "active" | "done" | "failed";
  detail?: string;
  count?: { current: number; total: number };
}

interface StepProgressProps {
  steps: Step[];
}

function StepIcon({ status }: { status: Step["status"] }) {
  switch (status) {
    case "done":
      return <Text color="green">✓</Text>;
    case "failed":
      return <Text color="red">✗</Text>;
    case "active":
      return <Text color="cyan"><Spinner type="dots" /></Text>;
    case "pending":
      return <Text dimColor>○</Text>;
  }
}

function StepLine({ step }: { step: Step }) {
  const countStr = step.count
    ? ` (${step.count.current}/${step.count.total})`
    : "";

  return (
    <Box flexDirection="column">
      <Box>
        <Text>  </Text>
        <StepIcon status={step.status} />
        <Text
          color={step.status === "failed" ? "red" : undefined}
          dimColor={step.status === "pending"}
        >
          {" "}{step.name}{countStr}
        </Text>
      </Box>
      {step.detail && step.status === "active" && (
        <Box marginLeft={4}>
          <Text dimColor>→ {step.detail}</Text>
        </Box>
      )}
    </Box>
  );
}

export function StepProgress({ steps }: StepProgressProps) {
  // Completed steps are rendered with <Static> so they don't re-render
  const doneSteps = steps.filter((s) => s.status === "done" || s.status === "failed");
  const liveSteps = steps.filter((s) => s.status === "active" || s.status === "pending");

  return (
    <Box flexDirection="column">
      <Static items={doneSteps}>
        {(step) => (
          <StepLine key={step.name} step={step} />
        )}
      </Static>
      {liveSteps.map((step) => (
        <StepLine key={step.name} step={step} />
      ))}
    </Box>
  );
}
