#!/usr/bin/env bun
import React from "react";
import { render } from "ink";
import { Command } from "commander";

import { InstallCommand } from "./commands/install.js";
import { UpdateCommand, updateCheck } from "./commands/update.js";
import { ReconfigureCommand } from "./commands/reconfigure.js";
import { ChangelogCommand } from "./commands/changelog.js";
import { UninstallCommand } from "./commands/uninstall.js";
import { CLI_VERSION, getRepoPath, getConfigVersion, isInteractive } from "./lib/platform.js";

const program = new Command()
  .name("jacks-nix")
  .description("Manage your jacks-nix system configuration")
  .version(CLI_VERSION, "-v, --version")
  .option("--non-interactive", "Skip prompts, use defaults/env vars")
  .option("--verbose", "Show full subprocess output");

// Global options
const globalOpts = () => {
  const opts = program.opts();
  return {
    nonInteractive: opts.nonInteractive || !isInteractive(),
    verbose: opts.verbose || false,
    repoPath: getRepoPath(),
  };
};

program
  .command("install")
  .description("Install jacks-nix (Nix, repo, configure, switch)")
  .action(() => {
    const opts = globalOpts();
    renderApp(<InstallCommand repoPath={opts.repoPath} nonInteractive={opts.nonInteractive} verbose={opts.verbose} />);
  });

program
  .command("update")
  .description("Update to the latest jacks-nix version")
  .action(() => {
    const opts = globalOpts();
    renderApp(<UpdateCommand repoPath={opts.repoPath} nonInteractive={opts.nonInteractive} verbose={opts.verbose} />);
  });

program
  .command("reconfigure")
  .description("Reconfigure jacks-nix options")
  .action(() => {
    const opts = globalOpts();
    renderApp(<ReconfigureCommand repoPath={opts.repoPath} nonInteractive={opts.nonInteractive} verbose={opts.verbose} />);
  });

program
  .command("changelog")
  .description("Browse changelogs interactively")
  .action(() => {
    const opts = globalOpts();
    renderApp(<ChangelogCommand repoPath={opts.repoPath} />);
  });

program
  .command("uninstall")
  .description("Uninstall jacks-nix configuration")
  .action(() => {
    const opts = globalOpts();
    renderApp(<UninstallCommand repoPath={opts.repoPath} nonInteractive={opts.nonInteractive} />);
  });

program
  .command("update-check")
  .description("Check for updates (non-blocking, for shell startup)")
  .action(async () => {
    const opts = globalOpts();
    try {
      await updateCheck(opts.repoPath);
    } catch {
      // Silently fail — this runs on every shell startup
    }
    process.exit(0);
  });

// Show help if no command given
program.action(() => {
  program.help();
});

// Global error handler
process.on("uncaughtException", (err) => {
  console.error(`\n  ❌ Unexpected error: ${err.message}`);
  console.error(`     ${err.stack?.split("\n")[1]?.trim() ?? ""}`);
  console.error(`\n     If this persists, please file an issue.`);
  process.exit(1);
});

process.on("unhandledRejection", (reason) => {
  console.error(`\n  ❌ Unexpected error: ${reason}`);
  process.exit(1);
});

// Render helper
function renderApp(element: React.ReactElement) {
  const { waitUntilExit } = render(element, {
    exitOnCtrlC: true,
  });

  waitUntilExit().then(() => {
    process.exit(0);
  });
}

// Parse and run
program.parse();
