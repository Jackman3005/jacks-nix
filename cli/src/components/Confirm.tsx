import React, { useState } from "react";
import { Box, Text, useInput, useApp } from "ink";

interface ConfirmProps {
  message?: string;
  onConfirm: () => void;
}

export function Confirm({ message = "Press Enter to proceed (Ctrl+C to cancel)...", onConfirm }: ConfirmProps) {
  const { exit } = useApp();
  const [confirmed, setConfirmed] = useState(false);

  useInput((input, key) => {
    if (key.return && !confirmed) {
      setConfirmed(true);
      onConfirm();
    }
    if (input === "c" && key.ctrl) {
      exit();
    }
  });

  return (
    <Box marginTop={1}>
      <Text dimColor>{confirmed ? "✓" : "›"} {message}</Text>
    </Box>
  );
}
