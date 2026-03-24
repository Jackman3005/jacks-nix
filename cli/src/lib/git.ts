import { join } from "node:path";
import { run } from "./subprocess.js";
import { getGitPath } from "./platform.js";

/** Clone the jacks-nix repo. */
export const cloneRepo = async (targetDir: string, logPath: string): Promise<number> =>
  (await run([getGitPath(), "clone", "--branch", "latest", "https://github.com/Jackman3005/jacks-nix.git", targetDir], { logPath })).exitCode;

/** Fetch the latest tag from origin. */
export const fetchLatestTag = async (repoPath: string, logPath: string): Promise<number> =>
  (await run([getGitPath(), "fetch", "origin", "tag", "latest", "--force"], { cwd: repoPath, logPath })).exitCode;

/** Check out the latest tag. */
export const checkoutLatest = async (repoPath: string, logPath: string): Promise<number> =>
  (await run([getGitPath(), "-c", "advice.detachedHead=false", "checkout", "tags/latest"], { cwd: repoPath, logPath })).exitCode;

/** Get the current HEAD commit hash. */
export const getHead = async (repoPath: string): Promise<string> =>
  (await run([getGitPath(), "rev-parse", "HEAD"], { cwd: repoPath })).stdout.trim();

/** Get the commit hash of tags/latest. */
export const getLatestTagHash = async (repoPath: string): Promise<string> =>
  (await run([getGitPath(), "rev-parse", "tags/latest"], { cwd: repoPath })).stdout.trim();

/** Get a file's content from a tag without checking out. */
export async function getFileFromTag(repoPath: string, tag: string, filePath: string): Promise<string | null> {
  const result = await run([getGitPath(), "show", `${tag}:${filePath}`], { cwd: repoPath });
  return result.exitCode === 0 ? result.stdout : null;
}

/** Check if the repo has uncommitted changes. */
export const isDirty = async (repoPath: string): Promise<boolean> =>
  (await run([getGitPath(), "status", "--porcelain"], { cwd: repoPath })).stdout.trim().length > 0;

/** Get VERSION from the repo. */
export async function getVersion(repoPath: string): Promise<string> {
  const file = Bun.file(join(repoPath, "VERSION"));
  return (await file.exists()) ? (await file.text()).trim() : "0";
}

/** Get VERSION from the remote latest tag. */
export async function getRemoteVersion(repoPath: string): Promise<string> {
  return (await getFileFromTag(repoPath, "tags/latest", "VERSION"))?.trim() || "0";
}

/** Configure git remotes for HTTPS pull / SSH push. */
export async function configureRemotes(repoPath: string, logPath: string): Promise<void> {
  const git = getGitPath();
  await run([git, "remote", "set-url", "origin", "https://github.com/Jackman3005/jacks-nix.git"], { cwd: repoPath, logPath });
  await run([git, "remote", "set-url", "--push", "origin", "git@github.com:Jackman3005/jacks-nix.git"], { cwd: repoPath, logPath });
}
