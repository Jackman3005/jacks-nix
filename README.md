# Jack's Nix Configuration

![macOS](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black)
![Nix](https://img.shields.io/badge/Nix-5277C3?logo=nixos&logoColor=white)
![Neovim](https://img.shields.io/badge/Neovim-57A143?logo=neovim&logoColor=white)
![Zsh](https://img.shields.io/badge/Zsh-F15A24?logo=zsh&logoColor=white)
![Homebrew](https://img.shields.io/badge/Homebrew-FBB040?logo=homebrew&logoColor=black)
![Git](https://img.shields.io/badge/Git-F05032?logo=git&logoColor=white)

![GitHub last commit](https://img.shields.io/github/last-commit/Jackman3005/jacks-nix)
![Works on my machine](https://img.shields.io/badge/Works%20on-My%20Machine-success)
![Dotfiles managed](https://img.shields.io/badge/Dotfiles-Managed-success)
![GitHub repo size](https://img.shields.io/github/repo-size/Jackman3005/jacks-nix)
![License](https://img.shields.io/github/license/Jackman3005/jacks-nix)

![Test and Tag](https://github.com/Jackman3005/jacks-nix/workflows/Test%20and%20Tag/badge.svg)
![Auto Flake Update](https://github.com/Jackman3005/jacks-nix/workflows/Auto%20Flake%20Update/badge.svg)

This repository contains my complete, cross-platform Nix configuration for macOS (via `nix-darwin`) and other Linux
distributions (via `home-manager`). It uses Nix Flakes to manage configurations from a single source of truth.

## Installation

The installation and update processes are automated. Simply run `./bin/install.sh` for initial setup or reinstallation.

You can simply run the one-line command for it to clone this repo and perform all initial setup operations.

**One Line Installation**

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Jackman3005/jacks-nix/latest/bin/install.sh)"
```

## Updating

To pull the latest changes and apply the nix flake, use the `update` alias.

## Upgrading

Use the `upgrade` alias to run `nix flake update` and subsequently attempt to update all packages in the nix flake.
If there are changes and git repo authorization is available, it will commit and push the updates.

> Note: An auto-updater runs regularly on GH to check for any updates and publish them to the repo.

## Structure

```
.
├── flake.nix                             # Main Nix flake entrypoint
├── bin/                                  # Scripts and executables
│   ├── install.sh                        # Universal installation script
├── hosts/                                # Host-specific configurations
│   ├── mac-arm64/
│   └── linux-x64/
├── nix-modules/                          # Shared, modular Home Manager configuration
│   ├── default.nix                       # Assembles all modules
│   ├── git.nix
│   ├── homebrew.nix
│   ├── nvim.nix
│   ├── updates.nix
│   └── shell.nix
├── config/                               # Where configuration options and defaults are specified
│   ├── default.nix
│   └── options.nix
├── local/                                # Ignored by git. Local machine-specific files.
│   └── last-update-check-timestamp.txt   # Helper that keeps track of last update check to avoid checking too often. Safe to delete.
└── assets/                               # Extra files/folders to be symlinked or copied.
    └── nvim/                             # Lazy NeoVIM configuration files.
```

## Configuration

You can customize the configuration using environment variables.
See [config/default.nix](./config/default.nix) for the definitive list of env var overrides.

### Environment Variables

All configuration options can be overridden using environment variables with the `JACKS_NIX_` prefix:

| Name                            | Default                   | Description                                              |
|---------------------------------|---------------------------|----------------------------------------------------------|
| `JACKS_NIX_USERNAME`            | "jack"                    | Your system username                                     |
| `JACKS_NIX_GIT_NAME`            | "Jack Coy"                | Your full name for Git configuration                     |
| `JACKS_NIX_GIT_EMAIL`           | "jackman3000@gmail.com"   | Your email address for Git configuration                 |
| `JACKS_NIX_GIT_SIGNING_KEY`     | "ssh-ed25519 ..."         | Your public signing key for git. Leave empty to disable. |
| `JACKS_NIX_ZSH_THEME`           | "ys"                      | Oh My Zsh theme to use                                   |
| `JACKS_NIX_ENABLE_GIT`          | true                      | Enable Git configuration                                 |
| `JACKS_NIX_ENABLE_ZSH`          | true                      | Enable Zsh and Oh My Zsh                                 |
| `JACKS_NIX_ENABLE_NVIM`         | true                      | Enable Neovim configuration                              |
| `JACKS_NIX_ENABLE_HOMEBREW`     | true (macOS only)         | Enable Homebrew (macOS only, true/false)                 |
| `JACKS_NIX_ENABLE_PYTHON`       | false                     | Enable Python development tools                          |
| `JACKS_NIX_ENABLE_NODE`         | false                     | Enable Node.js development tools                         |
| `JACKS_NIX_ENABLE_JAVA`         | false                     | Enable Java development tools                            |
| `JACKS_NIX_ENABLE_RUBY`         | false                     | Enable Ruby development tools                            |
| `JACKS_NIX_ENABLE_BUN`          | false                     | Enable Bun JavaScript runtime                            |
| `JACKS_NIX_ENABLE_ASDF`         | false                     | Enable ASDF version manager                              |
| `JACKS_NIX_CONFIG_REPO_PATH`    | "$HOME/.config/jacks-nix" | Path where this repository is stored                     |
| `JACKS_NIX_MAC_NIXBLD_USER_ID`  | 350                       | Override for nix-darwin `nixbld` UID                     |
| `JACKS_NIX_MAC_NIXBLD_GROUP_ID` | 350                       | Override for nix-darwin `nixbld` GID                     |

### Example

```bash
export JACKS_NIX_USERNAME="your-username"
export JACKS_NIX_GIT_NAME="Your Name"
export JACKS_NIX_GIT_EMAIL="your.email@example.com"
export JACKS_NIX_ZSH_THEME="robbyrussell"
export JACKS_NIX_ENABLE_PYTHON="true"
export JACKS_NIX_ENABLE_BUN="true"
```

## How It Works

This setup is built around a modular core in `nix-modules/` and `config/`.

- **`config/`**: Defines default configuration values and reads environment variable overrides.
- **`nix-modules/`**: Each file manages a specific piece of software (Git, Zsh, etc.), pulling values from your central
  config.
- **`hosts/`**: Contains minimal files that add OS-specific packages or settings.
- **`flake.nix`**: Assembles the correct configuration based on the target OS (`darwinConfigurations` for macOS,
  `homeConfigurations` for Linux).
