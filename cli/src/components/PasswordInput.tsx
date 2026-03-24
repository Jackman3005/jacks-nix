import React, { useState } from "react";
import { Box, Text, useInput } from "ink";

interface PasswordInputProps {
  prompt?: string;
  onSubmit: (password: string) => void;
  error?: string;
}

export function PasswordInput({ prompt = "Password", onSubmit, error }: PasswordInputProps) {
  const [value, setValue] = useState("");

  useInput((input, key) => {
    if (key.return) {
      onSubmit(value);
      setValue("");
      return;
    }
    if (key.backspace || key.delete) {
      setValue((v) => v.slice(0, -1));
      return;
    }
    // Ignore control characters
    if (key.ctrl || key.meta || key.escape) return;
    if (input) {
      setValue((v) => v + input);
    }
  });

  return (
    <Box flexDirection="column">
      <Box>
        <Text>  {prompt}: </Text>
        <Text>{value.length > 0 ? "•".repeat(value.length) : ""}</Text>
        <Text dimColor>▌</Text>
      </Box>
      {error && (
        <Box marginLeft={2}>
          <Text color="red">{error}</Text>
        </Box>
      )}
    </Box>
  );
}
