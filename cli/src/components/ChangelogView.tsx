import React from "react";
import { Box, Text } from "ink";
import type { PackageChange, PackageInfo } from "../lib/changelog.js";
import { formatBytes } from "../lib/changelog.js";

interface ChangelogViewProps {
  fromVersion: string;
  toVersion: string;
  upgrades: Map<string, PackageChange>;
  added: Map<string, PackageInfo>;
  removed: Map<string, PackageInfo>;
  commits: Array<{ sha: string; message: string; author: string }>;
  latestSizes: { linuxX64Bytes: number | null; macArm64Bytes: number | null };
  earliestSizes: { linuxX64Bytes: number | null; macArm64Bytes: number | null };
  /** Set of package names that are explicitly declared (not just dependencies). */
  declaredPackages?: Set<string>;
  /** When true, show all dependency upgrades with versions instead of just a count. */
  detailed?: boolean;
}

export function ChangelogView({
  fromVersion,
  toVersion,
  upgrades,
  added,
  removed,
  commits,
  latestSizes,
  earliestSizes,
  declaredPackages,
  detailed = false,
}: ChangelogViewProps) {
  // Split upgrades into key (declared) and dependency
  const keyUpgrades: PackageChange[] = [];
  const depUpgrades: PackageChange[] = [];
  for (const [, pkg] of upgrades) {
    if (declaredPackages?.has(pkg.name)) {
      keyUpgrades.push(pkg);
    } else {
      depUpgrades.push(pkg);
    }
  }

  const hasSizeChange =
    latestSizes.macArm64Bytes != null && earliestSizes.macArm64Bytes != null;

  return (
    <Box flexDirection="column" marginBottom={1}>
      {/* Version header */}
      <Box marginBottom={1}>
        <Text>  v{fromVersion} → v{toVersion}</Text>
      </Box>

      {/* Size changes */}
      {hasSizeChange && (
        <Box marginBottom={1} flexDirection="column">
          <Text bold>  Size</Text>
          {latestSizes.linuxX64Bytes != null && earliestSizes.linuxX64Bytes != null && (
            <SizeLine
              label="Linux"
              from={earliestSizes.linuxX64Bytes}
              to={latestSizes.linuxX64Bytes}
            />
          )}
          {latestSizes.macArm64Bytes != null && earliestSizes.macArm64Bytes != null && (
            <SizeLine
              label="macOS"
              from={earliestSizes.macArm64Bytes}
              to={latestSizes.macArm64Bytes}
            />
          )}
        </Box>
      )}

      {/* Key upgrades */}
      {keyUpgrades.length > 0 && (
        <Box flexDirection="column" marginBottom={1}>
          <Text bold>  Key Upgrades</Text>
          {keyUpgrades.map((pkg) => (
            <Box key={pkg.name} marginLeft={4}>
              <Text>
                <Text color="cyan">{pkg.name}</Text>
                {pkg.from && pkg.to && (
                  <Text dimColor>  {pkg.from} → {pkg.to}</Text>
                )}
              </Text>
            </Box>
          ))}
        </Box>
      )}

      {/* Dependency upgrades */}
      {depUpgrades.length > 0 && (
        <Box flexDirection="column" marginBottom={1}>
          <Text bold>  Dependency Upgrades</Text>
          {detailed ? (
            depUpgrades.map((pkg) => (
              <Box key={pkg.name} marginLeft={4}>
                <Text>
                  <Text dimColor>{pkg.name}</Text>
                  {pkg.from && pkg.to && (
                    <Text dimColor>  {pkg.from} → {pkg.to}</Text>
                  )}
                </Text>
              </Box>
            ))
          ) : (
            <Box marginLeft={4}>
              <Text dimColor>
                {depUpgrades.length} packages updated
              </Text>
            </Box>
          )}
        </Box>
      )}

      {/* Added packages */}
      {added.size > 0 && (
        <Box flexDirection="column" marginBottom={1}>
          <Text bold>  Added</Text>
          {[...added.values()].map((pkg) => (
            <Box key={pkg.name} marginLeft={4}>
              <Text color="green">+ {pkg.name}{pkg.version && pkg.version !== "<none>" ? ` ${pkg.version}` : ""}</Text>
            </Box>
          ))}
        </Box>
      )}

      {/* Removed packages */}
      {removed.size > 0 && (
        <Box flexDirection="column" marginBottom={1}>
          <Text bold>  Removed</Text>
          {[...removed.values()].map((pkg) => (
            <Box key={pkg.name} marginLeft={4}>
              <Text color="red">- {pkg.name}{pkg.version && pkg.version !== "<none>" ? ` ${pkg.version}` : ""}</Text>
            </Box>
          ))}
        </Box>
      )}

      {/* Manual commits */}
      {commits.length > 0 && (
        <Box flexDirection="column">
          <Text bold>  Changes</Text>
          {commits.map((c) => (
            <Box key={c.sha} marginLeft={4}>
              <Text>• {c.message}</Text>
            </Box>
          ))}
        </Box>
      )}
    </Box>
  );
}

function SizeLine({ label, from, to }: { label: string; from: number; to: number }) {
  const diff = to - from;
  const diffMB = Math.round(diff / 1_048_576);
  const color = diff > 0 ? "yellow" : diff < 0 ? "green" : undefined;
  const sign = diff > 0 ? "+" : "";
  const diffStr = diff === 0 ? "no change" : `${sign}${diffMB} MiB`;

  return (
    <Box marginLeft={4}>
      <Text>
        {label}: {formatBytes(from)} → {formatBytes(to)} (
        <Text color={color}>{diffStr}</Text>
        )
      </Text>
    </Box>
  );
}
