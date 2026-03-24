import React from "react";
import { Box, Text } from "ink";

interface ProgressBarProps {
  label: string;
  current: number;
  total: number;
  width?: number;
  showBytes?: boolean;
}

function formatSize(bytes: number): string {
  if (bytes >= 1_048_576) return `${(bytes / 1_048_576).toFixed(0)} MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${bytes} B`;
}

export function ProgressBar({ label, current, total, width = 20, showBytes = false }: ProgressBarProps) {
  const pct = total > 0 ? Math.min(current / total, 1) : 0;
  const filled = Math.round(pct * width);
  const empty = width - filled;
  const bar = "█".repeat(filled) + "░".repeat(empty);
  const pctStr = `${Math.round(pct * 100)}%`;

  const detail = showBytes && total > 0
    ? ` (${formatSize(current)}/${formatSize(total)})`
    : "";

  return (
    <Box>
      <Text>  {label} </Text>
      <Text color="cyan">{bar}</Text>
      <Text> {pctStr}{detail}</Text>
    </Box>
  );
}
