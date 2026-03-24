import type { ContentLine } from "../components/ScrollableView.js";
import type { PackageChange, PackageInfo } from "./changelog.js";
import { formatBytes } from "./changelog.js";

/**
 * Render changelog data to an array of ContentLine for use in ScrollableView.
 * This replaces the React-based ChangelogView for scrollable contexts.
 */
export function renderChangelog(opts: {
  fromVersion: string;
  toVersion: string;
  upgrades: Map<string, PackageChange>;
  added: Map<string, PackageInfo>;
  removed: Map<string, PackageInfo>;
  commits: Array<{ sha: string; message: string; author: string }>;
  latestSizes: { linuxX64Bytes: number | null; macArm64Bytes: number | null };
  earliestSizes: { linuxX64Bytes: number | null; macArm64Bytes: number | null };
  declaredPackages?: Set<string>;
  detailed?: boolean;
}): ContentLine[] {
  const lines: ContentLine[] = [];

  const {
    fromVersion, toVersion, upgrades, added, removed, commits,
    latestSizes, earliestSizes, declaredPackages, detailed,
  } = opts;

  // Version header
  lines.push({ text: `  v${fromVersion} → v${toVersion}`, bold: true });
  lines.push({ text: "" });

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

  // Size changes
  const hasSizeChange = latestSizes.macArm64Bytes != null && earliestSizes.macArm64Bytes != null;
  if (hasSizeChange) {
    lines.push({ text: "  Size", bold: true });
    if (latestSizes.linuxX64Bytes != null && earliestSizes.linuxX64Bytes != null) {
      lines.push({ text: `    Linux: ${formatSizeLine(earliestSizes.linuxX64Bytes, latestSizes.linuxX64Bytes)}` });
    }
    if (latestSizes.macArm64Bytes != null && earliestSizes.macArm64Bytes != null) {
      lines.push({ text: `    macOS: ${formatSizeLine(earliestSizes.macArm64Bytes, latestSizes.macArm64Bytes)}` });
    }
    lines.push({ text: "" });
  }

  // Key upgrades
  if (keyUpgrades.length > 0) {
    lines.push({ text: "  Key Upgrades", bold: true });
    for (const pkg of keyUpgrades) {
      const version = pkg.from && pkg.to ? `  ${pkg.from} → ${pkg.to}` : "";
      lines.push({ text: `    ${pkg.name}${version}`, color: "cyan" });
    }
    lines.push({ text: "" });
  }

  // Dependency upgrades
  if (depUpgrades.length > 0) {
    lines.push({ text: "  Dependency Upgrades", bold: true });
    if (detailed) {
      for (const pkg of depUpgrades) {
        const version = pkg.from && pkg.to ? `  ${pkg.from} → ${pkg.to}` : "";
        lines.push({ text: `    ${pkg.name}${version}`, dimColor: true });
      }
    } else {
      lines.push({ text: `    ${depUpgrades.length} packages updated`, dimColor: true });
    }
    lines.push({ text: "" });
  }

  // Added
  if (added.size > 0) {
    lines.push({ text: "  Added", bold: true });
    for (const [, pkg] of added) {
      const ver = pkg.version && pkg.version !== "<none>" ? ` ${pkg.version}` : "";
      lines.push({ text: `    + ${pkg.name}${ver}`, color: "green" });
    }
    lines.push({ text: "" });
  }

  // Removed
  if (removed.size > 0) {
    lines.push({ text: "  Removed", bold: true });
    for (const [, pkg] of removed) {
      const ver = pkg.version && pkg.version !== "<none>" ? ` ${pkg.version}` : "";
      lines.push({ text: `    - ${pkg.name}${ver}`, color: "red" });
    }
    lines.push({ text: "" });
  }

  // Commits
  if (commits.length > 0) {
    lines.push({ text: "  Changes", bold: true });
    for (const c of commits) {
      lines.push({ text: `    • ${c.message}` });
    }
    lines.push({ text: "" });
  }

  return lines;
}

function formatSizeLine(from: number, to: number): string {
  const diff = to - from;
  const diffMB = Math.round(diff / 1_048_576);
  const sign = diff > 0 ? "+" : "";
  const diffStr = diff === 0 ? "no change" : `${sign}${diffMB} MiB`;
  return `${formatBytes(from)} → ${formatBytes(to)} (${diffStr})`;
}
