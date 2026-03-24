import { join } from "node:path";
import { getFileFromTag } from "./git.js";

export interface PackageChange {
  name: string;
  from?: string;
  to?: string;
}

export interface PackageInfo {
  name: string;
  version?: string;
}

export interface ChangelogEntry {
  version: number;
  timestamp: string;
  closureSizes: { linuxX64Bytes: number | null; macArm64Bytes: number | null };
  packageChanges: {
    nvdAvailable: boolean;
    upgraded: PackageChange[];
    added: PackageInfo[];
    removed: PackageInfo[];
  };
  inputsChanged: Record<string, { commits?: number }>;
  manualCommits: Array<{ sha: string; message: string; author: string }>;
}

/** Raw changelog JSON shape (matches changelogs/*.json). */
interface RawChangelog {
  version: number;
  timestamp: string;
  closure_sizes?: { linux_x64_bytes?: number; mac_arm64_bytes?: number };
  package_changes?: {
    nvd_available?: boolean;
    upgraded?: Array<{ name: string; from_version?: string; to_version?: string }>;
    added?: Array<string | { name: string; version?: string }>;
    removed?: Array<string | { name: string; version?: string }>;
  };
  inputs_changed?: Record<string, { commits?: number }>;
  manual_commits?: Array<{ sha: string; message: string; author: string }>;
}

/** Normalize added/removed items (can be string or {name, version} object). */
function normalizePackageInfo(item: string | { name: string; version?: string }): PackageInfo {
  if (typeof item === "string") return { name: item };
  return { name: item.name, version: item.version };
}

/** Parse raw changelog JSON into typed entry. */
function parseChangelogJson(raw: RawChangelog): ChangelogEntry {
  return {
    version: raw.version,
    timestamp: raw.timestamp,
    closureSizes: {
      linuxX64Bytes: raw.closure_sizes?.linux_x64_bytes ?? null,
      macArm64Bytes: raw.closure_sizes?.mac_arm64_bytes ?? null,
    },
    packageChanges: {
      nvdAvailable: raw.package_changes?.nvd_available ?? false,
      upgraded: (raw.package_changes?.upgraded ?? []).map((u) => ({
        name: u.name, from: u.from_version, to: u.to_version,
      })),
      added: (raw.package_changes?.added ?? []).map(normalizePackageInfo),
      removed: (raw.package_changes?.removed ?? []).map(normalizePackageInfo),
    },
    inputsChanged: raw.inputs_changed ?? {},
    manualCommits: (raw.manual_commits ?? []).filter(
      (c) => !c.message.startsWith("AutoFlakeUpdater") && !/^v\d+: changelog/.test(c.message),
    ),
  };
}

/** Load a changelog from the repo. */
export async function loadChangelog(repoPath: string, version: number): Promise<ChangelogEntry | null> {
  const file = Bun.file(join(repoPath, "changelogs", `${version}.json`));
  if (!(await file.exists())) return null;
  return parseChangelogJson(await file.json());
}

/** Load a changelog from a git tag (before checkout). */
export async function loadChangelogFromTag(repoPath: string, version: number): Promise<ChangelogEntry | null> {
  const content = await getFileFromTag(repoPath, "tags/latest", `changelogs/${version}.json`);
  if (!content) return null;
  return parseChangelogJson(JSON.parse(content));
}

/** Aggregate changelogs between two versions (exclusive from, inclusive to). */
export async function aggregateChangelogs(
  repoPath: string,
  fromVersion: number,
  toVersion: number,
  options: { fromTag?: boolean } = {},
) {
  const upgrades = new Map<string, PackageChange>();
  const added = new Map<string, PackageInfo>();
  const removed = new Map<string, PackageInfo>();
  const commitsSeen = new Set<string>();
  const commits: Array<{ sha: string; message: string; author: string }> = [];
  let latestSizes = { linuxX64Bytes: null as number | null, macArm64Bytes: null as number | null };
  let earliestSizes = { linuxX64Bytes: null as number | null, macArm64Bytes: null as number | null };

  for (let v = fromVersion + 1; v <= toVersion; v++) {
    const entry = options.fromTag
      ? await loadChangelogFromTag(repoPath, v)
      : await loadChangelog(repoPath, v);
    if (!entry) continue;

    if (v === fromVersion + 1) earliestSizes = entry.closureSizes;
    if (v === toVersion) latestSizes = entry.closureSizes;

    // Combine multi-step upgrades: A→B then B→C = A→C
    for (const pkg of entry.packageChanges.upgraded) {
      const existing = upgrades.get(pkg.name);
      upgrades.set(pkg.name, existing
        ? { name: pkg.name, from: existing.from, to: pkg.to }
        : pkg);
    }

    for (const pkg of entry.packageChanges.added) added.set(pkg.name, pkg);
    for (const pkg of entry.packageChanges.removed) removed.set(pkg.name, pkg);

    for (const commit of entry.manualCommits) {
      if (!commitsSeen.has(commit.sha)) {
        commitsSeen.add(commit.sha);
        commits.push(commit);
      }
    }
  }

  return { upgrades, added, removed, commits, latestSizes, earliestSizes };
}

/** Format bytes as human-readable. */
export function formatBytes(bytes: number): string {
  if (bytes >= 1_073_741_824) return `${(bytes / 1_073_741_824).toFixed(1)} GiB`;
  if (bytes >= 1_048_576) return `${(bytes / 1_048_576).toFixed(0)} MiB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(0)} KiB`;
  return `${bytes} B`;
}
