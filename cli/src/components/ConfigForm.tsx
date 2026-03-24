import React, { useState } from "react";
import { Box, Text, useInput } from "ink";
import TextInput from "ink-text-input";
import type { Schema, SchemaEntry, ConfigValues } from "../lib/config.js";

export type ConfigFormMode = "install" | "update" | "reconfigure";

interface ConfigFormProps {
  schema: Schema;
  currentValues: ConfigValues;
  sources: Record<string, "env" | "saved" | "default">;
  mode: ConfigFormMode;
  /** Only these entries need prompting (for "update" mode — new keys only). */
  newEntries?: SchemaEntry[];
  onSubmit: (values: ConfigValues) => void;
}

type Phase = "identity" | "features" | "done";

/** A single text input field for identity group. */
function IdentityField({
  entry,
  value,
  isActive,
  isReadOnly,
  source,
  onChange,
  onSubmit,
}: {
  entry: SchemaEntry;
  value: string;
  isActive: boolean;
  isReadOnly: boolean;
  source?: "env" | "saved" | "default";
  onChange: (val: string) => void;
  onSubmit: () => void;
}) {
  if (isReadOnly || !isActive) {
    const sourceLabel = source === "env" ? " (from environment)" : "";
    return (
      <Box>
        <Text dimColor={!isActive}>
          {"  "}{entry.prompt}: {value}{sourceLabel}
        </Text>
      </Box>
    );
  }

  return (
    <Box>
      <Text>  {entry.prompt}: </Text>
      <TextInput
        value={value}
        onChange={onChange}
        onSubmit={onSubmit}
        placeholder={value || ""}
      />
    </Box>
  );
}

/** Multi-select toggle list for features group. */
function FeatureToggles({
  entries,
  values,
  activeIndex,
  isActive,
  sources,
}: {
  entries: SchemaEntry[];
  values: ConfigValues;
  activeIndex: number;
  isActive: boolean;
  sources: Record<string, "env" | "saved" | "default">;
}) {
  if (!isActive) {
    // Show summary
    return (
      <Box flexDirection="column">
        {entries.map((entry) => {
          const enabled = values[entry.key] === "true";
          const sourceLabel = sources[entry.key] === "env" ? " (env)" : "";
          return (
            <Box key={entry.key} marginLeft={2}>
              <Text color={enabled ? "green" : "gray"}>
                {enabled ? "◉" : "○"} {entry.prompt}{sourceLabel}
              </Text>
            </Box>
          );
        })}
      </Box>
    );
  }

  return (
    <Box flexDirection="column">
      <Text dimColor>  (↑↓ navigate, space toggle, enter confirm)</Text>
      {entries.map((entry, i) => {
        const enabled = values[entry.key] === "true";
        const isCursor = i === activeIndex;
        return (
          <Box key={entry.key} marginLeft={2}>
            <Text
              bold={isCursor}
              color={isCursor ? "cyan" : enabled ? "green" : "gray"}
            >
              {isCursor ? "› " : "  "}
              {enabled ? "◉" : "○"} {entry.prompt}
            </Text>
            {entry.warning && isCursor && !enabled && (
              <Text color="yellow"> ⚠ {entry.warning}</Text>
            )}
          </Box>
        );
      })}
    </Box>
  );
}

export function ConfigForm({
  schema,
  currentValues,
  sources,
  mode,
  newEntries,
  onSubmit,
}: ConfigFormProps) {
  const [values, setValues] = useState<ConfigValues>({ ...currentValues });
  const identityGroup = schema.groups.find((g) => g.name === "Identity");
  const featuresGroup = schema.groups.find((g) => g.name === "Features");

  // Determine which identity entries to prompt
  const identityEntries = identityGroup?.entries ?? [];
  const featureEntries = featuresGroup?.entries ?? [];

  const promptableIdentity = mode === "update" && newEntries
    ? identityEntries.filter((e) => newEntries.some((n) => n.key === e.key))
    : identityEntries;

  const promptableFeatures = mode === "update" && newEntries
    ? featureEntries.filter((e) => newEntries.some((n) => n.key === e.key))
    : featureEntries;

  // Skip phases with nothing to prompt
  const hasIdentity = promptableIdentity.length > 0;
  const hasFeatures = promptableFeatures.length > 0;

  const initialPhase: Phase = hasIdentity ? "identity" : hasFeatures ? "features" : "done";
  const [phase, setPhase] = useState<Phase>(initialPhase);
  const [identityIndex, setIdentityIndex] = useState(0);
  const [featureIndex, setFeatureIndex] = useState(0);

  // Handle feature toggles keyboard input
  useInput((input, key) => {
    if (phase !== "features") return;

    if (key.upArrow) {
      setFeatureIndex((i) => Math.max(0, i - 1));
    } else if (key.downArrow) {
      setFeatureIndex((i) => Math.min(promptableFeatures.length - 1, i + 1));
    } else if (input === " ") {
      const entry = promptableFeatures[featureIndex];
      setValues((v) => ({
        ...v,
        [entry.key]: v[entry.key] === "true" ? "false" : "true",
      }));
    } else if (key.return) {
      if (phase === "features") {
        onSubmit(values);
        setPhase("done");
      }
    }
  });

  const advanceIdentity = () => {
    const nextIndex = identityIndex + 1;
    if (nextIndex >= promptableIdentity.length) {
      if (hasFeatures) {
        setPhase("features");
      } else {
        onSubmit(values);
        setPhase("done");
      }
    } else {
      setIdentityIndex(nextIndex);
    }
  };

  if (phase === "done") return null;

  return (
    <Box flexDirection="column">
      {/* Identity group */}
      {identityEntries.length > 0 && (
        <Box flexDirection="column" marginBottom={1}>
          <Text bold>  Identity</Text>
          <Text dimColor>  ─────────</Text>
          {identityEntries.map((entry, i) => {
            const isPromptable = promptableIdentity.includes(entry);
            const isActive = phase === "identity" && isPromptable && i === identityIndex;
            const isReadOnly = mode === "reconfigure" && entry.readOnlyInReconfigure === true;

            return (
              <IdentityField
                key={entry.key}
                entry={entry}
                value={values[entry.key] ?? ""}
                isActive={isActive}
                isReadOnly={isReadOnly || !isPromptable}
                source={sources[entry.key]}
                onChange={(val) => setValues((v) => ({ ...v, [entry.key]: val }))}
                onSubmit={advanceIdentity}
              />
            );
          })}
        </Box>
      )}

      {/* Features group */}
      {featureEntries.length > 0 && (
        <Box flexDirection="column">
          <Text bold>  Features</Text>
          <Text dimColor>  ─────────</Text>
          <FeatureToggles
            entries={mode === "update" && newEntries ? promptableFeatures : featureEntries}
            values={values}
            activeIndex={featureIndex}
            isActive={phase === "features"}
            sources={sources}
          />
        </Box>
      )}
    </Box>
  );
}
