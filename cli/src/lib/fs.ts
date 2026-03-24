/**
 * Filesystem utilities.
 * Uses Bun-native APIs where available, node:fs for directories and append (no Bun equivalent yet).
 */
import {
  appendFileSync,
  mkdirSync as nodeMkdirSync,
  lstatSync,
  existsSync,
} from "node:fs";
import { mkdir as nodeMkdir, rm as nodeRm } from "node:fs/promises";

/** Create a directory recursively (async). */
export const mkdir = (path: string) => nodeMkdir(path, { recursive: true });

/** Create a directory recursively (sync). */
export const mkdirSync = (path: string, options?: { recursive?: boolean }) =>
  nodeMkdirSync(path, { recursive: options?.recursive ?? true });

/** Append text to a file (sync — used for logging where we don't want to await). */
export const appendFile = (path: string, text: string) =>
  appendFileSync(path, text);

/** Check if a path exists (async, Bun-native). */
export const exists = (path: string) => Bun.file(path).exists();

/** Check if a path exists (sync, node:fs — for use in sync contexts). */
export { existsSync } from "node:fs";

/** List directory contents (sync, node:fs — Bun has no native readdir yet). */
export { readdirSync } from "node:fs";

/** Check if a path is a symlink (sync). */
export const isSymlink = (path: string): boolean => {
  try {
    return lstatSync(path).isSymbolicLink();
  } catch {
    return false;
  }
};

/** Check if a path exists (sync). */
export const pathExists = (path: string): boolean => existsSync(path);

/** Delete a file (async, Bun-native). */
export const rm = (path: string) => Bun.file(path).delete();

/** Delete a file or directory recursively (async, node:fs). */
export const rmrf = (path: string) => nodeRm(path, { recursive: true, force: true });
