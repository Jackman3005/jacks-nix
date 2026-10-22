import { join } from "node:path";
import { mkdirSync } from "./fs.js";

// --- Types ---

export interface SchemaEntry {
  key: string;
  type: "string" | "bool";
  defaultKey?: string;
  defaultSource?: string;
  prompt: string;
  readOnlyInReconfigure?: boolean;
  warning?: string;
}

export interface SchemaGroup {
  name: string;
  entries: SchemaEntry[];
}

export interface Schema {
  groups: SchemaGroup[];
}

export type ConfigValues = Record<string, string>;

// --- Schema loading ---

export const loadSchema = (repoPath: string): Promise<Schema> =>
  Bun.file(join(repoPath, "config", "schema.json")).json();

export const loadDefaults = (repoPath: string): Promise<Record<string, unknown>> =>
  Bun.file(join(repoPath, "config", "defaults.json")).json();

/** Flatten all schema entries across groups. */
export const getAllEntries = (schema: Schema): SchemaEntry[] =>
  schema.groups.flatMap((g) => g.entries);

/** Resolve the default value for a schema entry. */
export function resolveDefault(entry: SchemaEntry, defaults: Record<string, unknown>): string {
  if (entry.defaultKey) {
    const val = defaults[entry.defaultKey];
    if (typeof val === "boolean") return val ? "true" : "false";
    return String(val ?? "");
  }
  if (entry.defaultSource?.startsWith("eval:")) {
    const cmd = entry.defaultSource.slice(5);
    const result = Bun.spawnSync(["bash", "-c", cmd]);
    return result.exitCode === 0 ? result.stdout.toString().trim() : "";
  }
  return "";
}

// --- Config file (local/config.json) ---

const configPath = (repoPath: string) => join(repoPath, "local", "config.json");

/** Load saved config. Returns empty object if missing. */
export async function loadConfig(repoPath: string): Promise<ConfigValues> {
  const file = Bun.file(configPath(repoPath));
  return (await file.exists()) ? file.json() : {};
}

// Domains reserved for documentation and testing (RFC 2606 / RFC 6761).
const PLACEHOLDER_DOMAINS = ["example.com", "example.org", "example.net"];
const RESERVED_TLDS = ["test", "example", "invalid", "localhost"];

/**
 * Why an email can't be used for Git commits, or null if it's fine.
 * Mirrors the assertion in nix-modules/git.nix.
 */
export function gitEmailProblem(email: string): string | null {
  const match = /^[^@\s]+@([^@\s]+\.[^@\s]+)$/.exec(email);
  if (!match) return "is not a valid email address";
  const domain = match[1].toLowerCase();
  const tld = domain.split(".").pop() ?? "";
  if (PLACEHOLDER_DOMAINS.includes(domain) || RESERVED_TLDS.includes(tld)) {
    return `uses a reserved test domain (${domain})`;
  }
  return null;
}

export interface SaveOptions {
  /**
   * Save values that came from the environment even when a different value is
   * already saved. Only `reconfigure` sets this, after the user confirms.
   */
  persistEnvOverrides?: boolean;
}

/**
 * Save config as JSON. Only writes current schema keys (drops deprecated).
 *
 * A value taken from a JACKS_NIX_* environment variable applies to this run
 * only: if a different value is already saved, the saved one is kept. A test
 * email once leaked into the saved config this way and was used for every commit
 * for months. A placeholder Git email is never saved.
 */
export async function saveConfig(
  repoPath: string,
  values: ConfigValues,
  schema: Schema,
  options: SaveOptions = {},
): Promise<void> {
  const saved = await loadConfig(repoPath);
  const filtered: ConfigValues = {};
  for (const entry of getAllEntries(schema)) {
    if (!(entry.key in values)) continue;
    let value = values[entry.key];
    const envValue = process.env[entry.key];
    const savedValue = saved[entry.key];
    if (
      !options.persistEnvOverrides &&
      envValue && value === envValue &&
      savedValue && savedValue !== value
    ) {
      value = savedValue;
    }
    filtered[entry.key] = value;
  }

  const email = filtered.JACKS_NIX_GIT_EMAIL;
  const problem = email === undefined ? null : gitEmailProblem(email);
  if (problem) {
    throw new Error(`Not saving config: Git email "${email}" ${problem}`);
  }

  mkdirSync(join(repoPath, "local"), { recursive: true });
  await Bun.write(configPath(repoPath), JSON.stringify(filtered, null, 2) + "\n");
}

/** Merge sources: env vars > saved config > defaults. */
export function mergeConfig(
  schema: Schema,
  defaults: Record<string, unknown>,
  savedConfig: ConfigValues,
): { values: ConfigValues; sources: Record<string, "env" | "saved" | "default"> } {
  const values: ConfigValues = {};
  const sources: Record<string, "env" | "saved" | "default"> = {};

  for (const entry of getAllEntries(schema)) {
    const envValue = process.env[entry.key];
    if (envValue !== undefined && envValue !== "") {
      values[entry.key] = envValue;
      sources[entry.key] = "env";
    } else if (entry.key in savedConfig && savedConfig[entry.key] !== "") {
      values[entry.key] = savedConfig[entry.key];
      sources[entry.key] = "saved";
    } else {
      values[entry.key] = resolveDefault(entry, defaults);
      sources[entry.key] = "default";
    }
  }
  return { values, sources };
}

/** Find schema entries not in saved config and not set via env. */
export const findNewEntries = (schema: Schema, savedConfig: ConfigValues): SchemaEntry[] =>
  getAllEntries(schema).filter(
    (e) => !(e.key in savedConfig) && !process.env[e.key],
  );

/** Check if saved config exists. */
export const hasConfig = async (repoPath: string): Promise<boolean> =>
  Bun.file(configPath(repoPath)).exists();

/** Record the applied version. */
export async function recordAppliedVersion(repoPath: string): Promise<void> {
  const versionFile = Bun.file(join(repoPath, "VERSION"));
  if (await versionFile.exists()) {
    mkdirSync(join(repoPath, "local"), { recursive: true });
    await Bun.write(join(repoPath, "local", "applied-version.txt"), (await versionFile.text()).trim() + "\n");
  }
}

/** Get the applied version, or "0". */
export async function getAppliedVersion(repoPath: string): Promise<string> {
  const file = Bun.file(join(repoPath, "local", "applied-version.txt"));
  return (await file.exists()) ? (await file.text()).trim() : "0";
}

/** Export config values as env vars (for nix evaluation via --impure). */
export function exportConfigToEnv(values: ConfigValues): void {
  for (const [key, val] of Object.entries(values)) process.env[key] = val;
}

/** Build env args for sudo passthrough: ["KEY=value", ...] */
export const buildEnvArgs = (values: ConfigValues): string[] =>
  Object.entries(values)
    .filter(([key]) => key.startsWith("JACKS_NIX_"))
    .map(([key, val]) => `${key}=${val}`);
