import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gitEmailProblem, loadConfig, saveConfig, type Schema } from "./config.js";

// Every test writes to a throwaway repo dir, never the real local/ config.

const schema: Schema = {
  groups: [{
    name: "git",
    entries: [
      { key: "JACKS_NIX_GIT_NAME", type: "string", prompt: "Name" },
      { key: "JACKS_NIX_GIT_EMAIL", type: "string", prompt: "Email" },
    ],
  }],
};

let repo: string;
const envBefore = { ...process.env };

beforeEach(() => {
  repo = mkdtempSync(join(tmpdir(), "jacks-nix-config-test-"));
  delete process.env.JACKS_NIX_GIT_NAME;
  delete process.env.JACKS_NIX_GIT_EMAIL;
});

afterEach(() => {
  rmSync(repo, { recursive: true, force: true });
  process.env = { ...envBefore };
});

describe("gitEmailProblem", () => {
  test.each([
    "test$special@example.com", "ci@EXAMPLE.org", "a@build.test", "a@foo.invalid",
    "a@host.localhost", "a@thing.example", "no-at-sign", "two@@at.com", "sp ace@x.com", "",
  ])("rejects %p", (email) => {
    expect(gitEmailProblem(email)).not.toBeNull();
  });

  test.each(["jackman3000@gmail.com", "first.last+tag@sub.domain.co.uk", "me@examples.com"])(
    "accepts %p",
    (email) => {
      expect(gitEmailProblem(email)).toBeNull();
    },
  );
});

describe("saveConfig", () => {
  const good = { JACKS_NIX_GIT_NAME: "Jack Coy", JACKS_NIX_GIT_EMAIL: "jackman3000@gmail.com" };

  test("saves on first run, including values from the environment", async () => {
    process.env.JACKS_NIX_GIT_EMAIL = "ci@real-domain.dev";
    await saveConfig(repo, { ...good, JACKS_NIX_GIT_EMAIL: "ci@real-domain.dev" }, schema);
    expect((await loadConfig(repo)).JACKS_NIX_GIT_EMAIL).toBe("ci@real-domain.dev");
  });

  test("does not let an environment override replace a saved value", async () => {
    await saveConfig(repo, good, schema);
    process.env.JACKS_NIX_GIT_EMAIL = "someone.else@real-domain.dev";
    await saveConfig(repo, { ...good, JACKS_NIX_GIT_EMAIL: "someone.else@real-domain.dev" }, schema);
    expect((await loadConfig(repo)).JACKS_NIX_GIT_EMAIL).toBe("jackman3000@gmail.com");
  });

  test("reconfigure can persist an environment value", async () => {
    await saveConfig(repo, good, schema);
    process.env.JACKS_NIX_GIT_EMAIL = "new.address@real-domain.dev";
    await saveConfig(
      repo,
      { ...good, JACKS_NIX_GIT_EMAIL: "new.address@real-domain.dev" },
      schema,
      { persistEnvOverrides: true },
    );
    expect((await loadConfig(repo)).JACKS_NIX_GIT_EMAIL).toBe("new.address@real-domain.dev");
  });

  test("refuses a placeholder email and writes nothing", async () => {
    await expect(
      saveConfig(repo, { ...good, JACKS_NIX_GIT_EMAIL: "test$special@example.com" }, schema),
    ).rejects.toThrow(/reserved test domain/);
    expect(await loadConfig(repo)).toEqual({});
  });
});
