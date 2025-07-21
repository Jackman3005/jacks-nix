#!/usr/bin/env bash
#
# Universal installer for jacks-nix configuration.
#
# This script is idempotent and can be run for both initial installation
# and subsequent updates. It will:
#
# 1. Check for and install necessary dependencies (Git, Nix, Xcode Tools on macOS).
# 2. Clone or update the repository in ~/.config/jacks-nix.
# 3. Configure the 'origin' remote for HTTPS pulls and SSH pushes.
# 4. Activate the appropriate Nix configuration for the host OS.

set -euo pipefail

# --- Configuration ---
readonly CLONE_DIR="${JACKS_NIX_CONFIG_REPO_PATH:-$HOME/.config/jacks-nix}"
readonly GIT_PULL_URL="https://github.com/Jackman3005/jacks-nix.git"
readonly GIT_PUSH_URL="git@github.com:Jackman3005/jacks-nix.git"
readonly LOG_FILE="/tmp/jacks-nix-setup.log"
readonly NIX_CONFIG_DIR="$HOME/.config/nix"
readonly NIX_CONFIG_FILE="$NIX_CONFIG_DIR/nix.conf"


# --- Helper Functions ---
_log() {
  # Log message to the log file
  printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

info() {
  # Print info message to stdout and log file
  local msg="$1"
  printf "\033[0;34m[INFO]\033[0m %s\n" "$msg"
  _log "INFO: $msg"
}

error() {
  # Print error message to stderr and log file, then exit
  local msg="$1"
  printf "\033[0;31m[ERROR]\033[0m %s\n" "$msg" >&2
  _log "ERROR: $msg"
  exit 1
}

ensure_dependency() {
  local name="$1"
  local check_cmd="$2"
  local install_cmd="$3"

  info "Checking for dependency: $name..."
  if eval "$check_cmd" &>/dev/null; then
    info "✅ $name is already installed."
  else
    info "⚠️ $name not found. Attempting to install..."
    _log "Installing dependency: $name"
    if eval "$install_cmd" >> "$LOG_FILE" 2>&1; then
      info "✅ Successfully installed $name."
    else
      error "Failed to install $name. Please install it manually and re-run the script."
    fi
  fi
}


ensure_nix_experimental_features() {
  info "Ensuring Nix experimental features are enabled..."
  local required_line="experimental-features = nix-command flakes"

  # Create config directory and file if they don't exist
  mkdir -p "$NIX_CONFIG_DIR"
  touch "$NIX_CONFIG_FILE"

  if grep -q "experimental-features" "$NIX_CONFIG_FILE"; then
    info "Nix 'experimental-features' already configured."
  else
    info "Adding 'experimental-features' to $NIX_CONFIG_FILE..."
    # Add a newline before the line to ensure it's not appended to an existing line
    printf "\n%s\n" "$required_line" >> "$NIX_CONFIG_FILE"
    info "✅ Configuration updated."
    info "You might need to restart the nix-daemon: 'sudo systemctl restart nix-daemon.service'"
  fi
}

ensure_user_config() {
  info "Checking user configuration environment variables..."

  # Check if user configuration environment variables are already set
  if [ -n "${JACKS_NIX_USER_USERNAME:-}" ] && [ -n "${JACKS_NIX_USER_NAME:-}" ] && [ -n "${JACKS_NIX_USER_EMAIL:-}" ]; then
    info "✅ User configuration found in environment variables:"
    info "   Username: $JACKS_NIX_USER_USERNAME"
    info "   Name: $JACKS_NIX_USER_NAME"
    info "   Email: $JACKS_NIX_USER_EMAIL"
    return
  fi

  echo
  info "⚠️ User configuration environment variables not found. Let's set them up."
  info "   These will be exported to your shell profile for future use."
  echo

  # --- Prompt for user details ---
  local default_username
  default_username=$(whoami)
  local default_git_name
  default_git_name=$(git config --global user.name || echo "")
  local default_git_email
  default_git_email=$(git config --global user.email || echo "")

  local user_username
  local user_name
  local user_email

  read -r -p "Enter your system username [default: $default_username]: " user_username
  user_username=${user_username:-$default_username}

  read -r -p "Enter your full name for Git [default: '$default_git_name']: " user_name
  user_name=${user_name:-$default_git_name}
  if [ -z "$user_name" ]; then
      error "Full name cannot be empty."
  fi

  read -r -p "Enter your email for Git [default: '$default_git_email']: " user_email
  user_email=${user_email:-$default_git_email}
  if [ -z "$user_email" ]; then
      error "Email cannot be empty."
  fi

  # Export environment variables for current session
  export JACKS_NIX_USER_USERNAME="$user_username"
  export JACKS_NIX_USER_NAME="$user_name"
  export JACKS_NIX_USER_EMAIL="$user_email"

  echo
  info "✅ User configuration environment variables set for current session."
  info "   To make these permanent, add the following to your shell profile or `~/.zshrc.local`:"
  echo
  echo "export JACKS_NIX_USER_USERNAME=\"$user_username\""
  echo "export JACKS_NIX_USER_NAME=\"$user_name\""
  echo "export JACKS_NIX_USER_EMAIL=\"$user_email\""
  echo
}

# --- Main Execution ---
main() {
  # Ensure the log file exists and has a start marker
  printf "\n\n--- Starting Jack's Nix Setup: %s ---\n" "$(date)" >> "$LOG_FILE"
  info "Starting setup. For detailed logs, run: tail -f ${LOG_FILE}"

  # 1. Prerequisite Checks
  if [[ "$(uname -s)" == "Darwin" ]]; then
    ensure_dependency "Xcode Command Line Tools" \
      "xcode-select -p" \
      "xcode-select --install"
  fi

  ensure_dependency "Git" \
    "command -v git" \
    "error 'Git is not installed. Please install it using your system package manager.'"

  # For Nix, we have a special case because it requires a shell restart
  info "Checking for dependency: Nix..."
  if ! command -v nix &>/dev/null; then
    info "Nix not found. The official Nix installer will be run."
    info "After installation, you MUST open a new terminal and re-run this script."
    read -p "Press [Enter] to continue with Nix installation..."
    # Run the official multi-user installer
    sh <(curl -L https://nixos.org/nix/install) --daemon
    error "Nix installation started. Please open a new terminal and re-run this script."
  else
    info "✅ Nix is already installed."
  fi


  # Ensure Nix config is set up for flakes
  ensure_nix_experimental_features

  # 2. Clone or Update Repository
  if [ -n "${JACKS_NIX_CONFIG_REPO_PATH:-}" ]; then
    info "Using existing directory at '$CLONE_DIR' (JACKS_NIX_CONFIG_REPO_PATH is set)..."
    if [ ! -d "$CLONE_DIR" ]; then
      error "JACKS_NIX_CONFIG_REPO_PATH is set to '$JACKS_NIX_CONFIG_REPO_PATH' but directory does not exist."
    fi
  elif [ -d "$CLONE_DIR" ]; then
    info "Directory '$CLONE_DIR' already exists. Updating repository..."
    cd "$CLONE_DIR"
    git pull --rebase --autostash
  else
    info "Cloning jacks-nix repository to '$CLONE_DIR'..."
    git clone "$GIT_PULL_URL" "$CLONE_DIR"
  fi

  # 3. Configure Git Remotes
  cd "$CLONE_DIR"
  if [ -z "${JACKS_NIX_CONFIG_REPO_PATH:-}" ]; then
    info "Setting git remotes to ensure correct pull/push configuration..."
    git remote set-url origin "$GIT_PULL_URL"
    git remote set-url --push origin "$GIT_PUSH_URL"
    info "Pull URL set to: $(git remote get-url origin)"
    info "Push URL set to: $(git remote get-url --push origin)"
  else
    info "Skipping git remote configuration (using existing repository from JACKS_NIX_CONFIG_REPO_PATH)..."
  fi

  # 4. Setup local configuration
  ensure_user_config

  # 5. Activate Nix Configuration
  info "Activating Nix configuration for this system..."
  case "$(uname -s)" in
    Darwin)
      info "Detected macOS. Applying nix-darwin configuration..."
      info "This may require your password to modify system-wide symlinks."
      sudo nix run --impure --extra-experimental-features nix-command --extra-experimental-features flakes nix-darwin -- switch --flake ".#mac-arm64" --impure
      ;;
    Linux)
      info "Detected Linux. Applying home-manager configuration..."
      nix run --impure --extra-experimental-features nix-command --extra-experimental-features flakes home-manager -- switch --impure --flake ".#linux-x64"
      ;;
    *)
      error "Unsupported Operating System: $(uname -s)"
      ;;
  esac

  echo
  info "✅ Jack's Nix setup is complete!"
  info "Please restart your shell for all changes to take effect."
}

# Run the main function
main "$@"
