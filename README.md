# Jack's Nix Configuration

This repository contains my complete, cross-platform Nix configuration for macOS (via `nix-darwin`) and other Linux distributions (via `home-manager`). It uses Nix Flakes to manage configurations from a single source of truth.

## Structure

```
.
├── flake.nix         # Main Nix flake entrypoint
├── install.sh        # Universal installation script
├── hosts/              # Host-specific configurations
│   ├── mac-arm64/
│   └── ubuntu-x64/
├── nix-modules/        # Shared, modular Home Manager configuration
│   ├── default.nix     # Assembles all modules
│   ├── git.nix
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

## Installation and Updates

The installation and update processes are automated. Simply run `./install.sh` for initial setup.

To apply local changes, use the `update` alias, which is now configured to work correctly on either platform.
