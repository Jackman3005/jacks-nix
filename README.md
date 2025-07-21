# Jack's Nix Configuration

This repository contains my complete, cross-platform Nix configuration for macOS (via `nix-darwin`) and other Linux distributions (via `home-manager`). It uses Nix Flakes to manage configurations from a single source of truth.

## Installation

The installation and update processes are automated. Simply run `./bin/install.sh` for initial setup or reinstallation.

You can simply run the one-line command for it to clone this repo and perform all initial setup operations.
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Jackman3005/jacks-nix/latest/bin/install.sh)"
```

## Updating
To pull the latest changes and apply the nix flake, use the `update` alias.

## Upgrading
Use the `upgrade` alias to update all packages in the nix flake.

> Note: This command will perform the upgrade for everyone, but the automatic commit part will only work for contributors.

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

You can customize the configuration using environment variables. The install script will prompt you for basic user information and set up the necessary environment variables.

### Environment Variables

All configuration options can be overridden using environment variables with the `JACKS_NIX_` prefix:

**User Information:**
- `JACKS_NIX_USER_USERNAME` - Your system username
- `JACKS_NIX_USER_NAME` - Your full name for Git configuration
- `JACKS_NIX_USER_EMAIL` - Your email address for Git configuration

**Feature Toggles:**
- `JACKS_NIX_ENABLE_GIT` - Enable Git configuration (true/false)
- `JACKS_NIX_ENABLE_ZSH` - Enable Zsh and Oh My Zsh (true/false)
- `JACKS_NIX_ENABLE_NVIM` - Enable Neovim configuration (true/false)
- `JACKS_NIX_ENABLE_HOMEBREW` - Enable Homebrew (macOS only, true/false)
- `JACKS_NIX_ENABLE_PYTHON` - Enable Python development tools (true/false)
- `JACKS_NIX_ENABLE_NODE` - Enable Node.js development tools (true/false)
- `JACKS_NIX_ENABLE_JAVA` - Enable Java development tools (true/false)
- `JACKS_NIX_ENABLE_RUBY` - Enable Ruby development tools (true/false)
- `JACKS_NIX_ENABLE_BUN` - Enable Bun JavaScript runtime (true/false)
- `JACKS_NIX_ENABLE_ASDF` - Enable ASDF version manager (true/false)

**Other Options:**
- `JACKS_NIX_CONFIG_REPO_PATH` - Path where the repository is stored
- `JACKS_NIX_ZSH_THEME` - Oh My Zsh theme to use

### Example

```bash
export JACKS_NIX_USER_NAME="Your Name"
export JACKS_NIX_USER_EMAIL="your.email@example.com"
export JACKS_NIX_ENABLE_PYTHON="true"
export JACKS_NIX_ENABLE_BUN="true"
```

## How It Works

This setup is built around a modular core in `nix-modules/` and `config/`.

- **`config/`**: Defines default configuration values and reads environment variable overrides.
- **`nix-modules/`**: Each file manages a specific piece of software (Git, Zsh, etc.), pulling values from your central config.
- **`hosts/`**: Contains minimal files that add OS-specific packages or settings.
- **`flake.nix`**: Assembles the correct configuration based on the target OS (`darwinConfigurations` for macOS, `homeConfigurations` for Linux).
