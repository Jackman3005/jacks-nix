#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}Jack's Nix Configuration Installer${NC}"
echo "=================================="
echo

# Function to create symlink with backup
create_symlink() {
    local source="$1"
    local target="$2"
    local target_dir="$(dirname "$target")"

    # Create target directory if it doesn't exist
    if [[ ! -d "$target_dir" ]]; then
        echo -e "${YELLOW}Creating directory: $target_dir${NC}"
        mkdir -p "$target_dir"
    fi

    # If target exists and is not a symlink, back it up
    if [[ -e "$target" && ! -L "$target" ]]; then
        local backup="${target}.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}Backing up existing file: $target -> $backup${NC}"
        mv "$target" "$backup"
    elif [[ -L "$target" ]]; then
        echo -e "${YELLOW}Removing existing symlink: $target${NC}"
        rm "$target"
    fi

    # Create the symlink
    echo -e "${GREEN}Creating symlink: $target -> $source${NC}"
    ln -sf "$source" "$target"
}

# Function to install Nix
install_nix() {
    echo -e "${BLUE}Installing Nix package manager...${NC}"
    echo

    # Detect platform
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${YELLOW}Detected macOS${NC}"
        # Use the official Nix installer with multi-user installation
        curl -L https://nixos.org/nix/install | sh -s -- --daemon
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo -e "${YELLOW}Detected Linux${NC}"
        # Check if systemd is available for multi-user installation
        if command -v systemctl &> /dev/null; then
            echo -e "${YELLOW}Using multi-user installation (recommended)${NC}"
            curl -L https://nixos.org/nix/install | sh -s -- --daemon
        else
            echo -e "${YELLOW}Using single-user installation${NC}"
            curl -L https://nixos.org/nix/install | sh -s -- --no-daemon
        fi
    else
        echo -e "${RED}Unsupported platform: $OSTYPE${NC}"
        echo "Please install Nix manually from: https://nixos.org/download.html"
        exit 1
    fi

    echo
    echo -e "${GREEN}Nix installation completed!${NC}"
    echo -e "${YELLOW}Please restart your shell or run: source ~/.nix-profile/etc/profile.d/nix.sh${NC}"
    echo -e "${YELLOW}Then run this script again to continue with configuration.${NC}"
    exit 0
}

# Main installation logic
main() {
    # Check if Nix is installed
    if ! command -v nix &> /dev/null; then
        install_nix
        # The script exits here after Nix installation
    fi


    echo -e "${BLUE}Ensuring configuration directory exists...${NC}"
    local config_dir="$HOME/.config/nix-config"
    mkdir -p "$(dirname "$config_dir")"

    echo -e "${BLUE}Symlinking repository to $config_dir...${NC}"
    # Symlink the entire repo to a known location
    if [ -L "$config_dir" ]; then
        echo -e "${YELLOW}Removing existing symlink: $config_dir${NC}"
        rm "$config_dir"
    elif [ -d "$config_dir" ]; then
        # Backup if it's a directory but not a symlink
        local backup_dir="${config_dir}.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}Backing up existing directory: $config_dir -> $backup_dir${NC}"
        mv "$config_dir" "$backup_dir"
    fi
    ln -s "$SCRIPT_DIR" "$config_dir"
    echo -e "${GREEN}Symlink created.${NC}"

    echo -e "${BLUE}Applying Nix configuration...${NC}"
    cd "$config_dir"

    # Apply the configuration based on the OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${YELLOW}Detected macOS. Applying darwin configuration...${NC}"
        # --- MODIFIED: Added sudo for system activation ---
        # This command requires root to modify system-level files.
        sudo nix --extra-experimental-features nix-command --extra-experimental-features flakes run nix-darwin -- switch --flake ".#mac-arm64"

    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo -e "${YELLOW}Detected Linux. Applying home-manager configuration...${NC}"
        # This command remains the same
        home-manager switch --flake ".#ubuntu-x64"

    else
        echo -e "${RED}Unsupported OS for automatic applying: $OSTYPE${NC}"
        echo -e "${YELLOW}You can try to apply a configuration manually.${NC}"
        exit 1
    fi

    echo
    echo -e "${GREEN}Configuration successfully applied!${NC}"
}

main
