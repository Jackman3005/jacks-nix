import React from "react";
import { Box, Text } from "ink";
import type { Schema, ConfigValues } from "../lib/config.js";

interface ConfigSummaryProps {
  schema: Schema;
  values: ConfigValues;
  sources?: Record<string, "env" | "saved" | "default">;
}

export function ConfigSummary({ schema, values, sources }: ConfigSummaryProps) {
  return (
    <Box flexDirection="column">
      {schema.groups.map((group) => (
        <Box key={group.name} flexDirection="column" marginBottom={1}>
          <Text bold>  {group.name}</Text>
          <Text dimColor>  ─────────</Text>
          {group.entries.map((entry) => {
            const val = values[entry.key] ?? "";
            const source = sources?.[entry.key];
            const sourceLabel = source === "env" ? " (from environment)" : "";

            if (entry.type === "bool") {
              const enabled = val === "true";
              return (
                <Box key={entry.key} marginLeft={2}>
                  <Text color={enabled ? "green" : "gray"}>
                    {enabled ? "◉" : "○"} {entry.prompt}{sourceLabel}
                  </Text>
                </Box>
              );
            }

            // Truncate long values (like signing keys)
            const displayVal = val.length > 50 ? val.slice(0, 47) + "..." : val;
            return (
              <Box key={entry.key} marginLeft={2}>
                <Text>
                  {entry.prompt}: <Text bold>{displayVal}</Text>
                  <Text dimColor>{sourceLabel}</Text>
                </Text>
              </Box>
            );
          })}
        </Box>
      ))}
    </Box>
  );
}

/** Show a diff of config changes (old vs new). */
export function ConfigDiff({
  schema,
  oldValues,
  newValues,
}: {
  schema: Schema;
  oldValues: ConfigValues;
  newValues: ConfigValues;
}) {
  const changes = schema.groups
    .flatMap((g) => g.entries)
    .filter((e) => oldValues[e.key] !== newValues[e.key]);

  if (changes.length === 0) {
    return (
      <Box marginLeft={2}>
        <Text dimColor>No changes.</Text>
      </Box>
    );
  }

  return (
    <Box flexDirection="column" marginBottom={1}>
      <Text bold>  Changes:</Text>
      {changes.map((entry) => {
        const oldVal = oldValues[entry.key] ?? "";
        const newVal = newValues[entry.key] ?? "";

        if (entry.type === "bool") {
          return (
            <Box key={entry.key} marginLeft={4}>
              <Text>
                {entry.prompt}: <Text color="red">{oldVal}</Text> → <Text color="green">{newVal}</Text>
              </Text>
            </Box>
          );
        }

        const oldDisplay = oldVal.length > 30 ? oldVal.slice(0, 27) + "..." : oldVal;
        const newDisplay = newVal.length > 30 ? newVal.slice(0, 27) + "..." : newVal;
        return (
          <Box key={entry.key} marginLeft={4}>
            <Text>
              {entry.prompt}: <Text color="red">{oldDisplay}</Text> → <Text color="green">{newDisplay}</Text>
            </Text>
          </Box>
        );
      })}
    </Box>
  );
}
