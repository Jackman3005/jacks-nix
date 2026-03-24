import React from "react";
import { Box, Text } from "ink";

interface HeaderProps {
  icon: string;
  title: string;
}

export function Header({ icon, title }: HeaderProps) {
  return (
    <Box flexDirection="column" marginBottom={1}>
      <Box>
        <Text bold>
          ┌─────────────────────────────────────────────┐
        </Text>
      </Box>
      <Box>
        <Text bold>
          │  {icon}  {title.padEnd(39)}│
        </Text>
      </Box>
      <Box>
        <Text bold>
          └─────────────────────────────────────────────┘
        </Text>
      </Box>
    </Box>
  );
}
