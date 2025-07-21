# Jack's Nix Configuration

This repository contains my complete, cross-platform Nix configuration for macOS (via `nix-darwin`) and other Linux distributions (via `home-manager`). It uses Nix Flakes to manage configurations from a single source of truth.

## Installation

The installation and update processes are automated. Simply run `./install.sh` for initial setup or reinstallation.

You can simply run the one-line command for it to clone this repo and perform all initial setup operations.
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Jackman3005/jacks-nix/latest/install.sh)"
```

## Updating
To pull the latest changes and apply the nix flake, use the `update` alias.

## Upgrading
Use the `upgrade` alias to update all packages in the nix flake.

> Note: This command will perform the upgrade for everyone, but the automatic commit part will only work for contributors.

## Structure
```
.
├── flake.nix         # Main Nix flake entrypoint
├── install.sh        # Universal installation script
├── hosts/              # Host-specific configurations
│   ├── mac-arm64/
│   └── linux-x64/
├── nix-modules/        # Shared, modular Home Manager configuration
│   ├── default.nix     # Assembles all modules
│   ├── git.nix
│   ├── homebrew.nix
│   ├── nvim.nix
│   └── shell.nix
├── config/             # Your personal configuration values and options
│   ├── default.nix     # <-- SET YOUR PERSONAL VALUES HERE
│   └── options.nix
└── dotfiles/           # Dotfiles/folders to be symlinked
    └── nvim/
```

## How It Works

This setup is built around a modular core in `nix-modules/` and `config/`.

- **`config/`**: You define your personal info (user, email) and toggle features on/off.
- **`nix-modules/`**: Each file manages a specific piece of software (Git, Zsh, etc.), pulling values from your central config.
- **`hosts/`**: Contains minimal files that add OS-specific packages or settings.
- **`flake.nix`**: Assembles the correct configuration based on the target OS (`darwinConfigurations` for macOS, `homeConfigurations` for Linux).
