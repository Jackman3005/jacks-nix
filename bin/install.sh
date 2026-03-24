#!/usr/bin/env bash
#
# Bootstrap installer for jacks-nix.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Jackman3005/jacks-nix/latest/bin/install.sh | bash
#   install.sh --cli-only             # Download CLI binary to local/ (repo must exist)
#   install.sh                        # Full install via CLI binary

set -euo pipefail

BINARY_NAME="jacks-nix"
REPO_URL="https://github.com/Jackman3005/jacks-nix/releases/download/latest"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)  PLATFORM="darwin-arm64" ;;
  Linux-x86_64)  PLATFORM="linux-x64" ;;
  *)
    echo "Unsupported platform: $(uname -s)-$(uname -m)"
    exit 1
    ;;
esac

download_cli_binary() {
  local dest="$1"
  echo "Downloading jacks-nix CLI binary..."
  mkdir -p "$(dirname "$dest")"
  curl -fsSL "${REPO_URL}/${BINARY_NAME}-${PLATFORM}" -o "$dest"
  chmod +x "$dest"
  echo "CLI binary ready."
}

if [[ "${1:-}" == "--cli-only" ]]; then
  REPO_PATH="${JACKS_NIX_CONFIG_REPO_PATH:-$HOME/.config/jacks-nix}"
  if [[ ! -d "$REPO_PATH" ]]; then
    echo "Repository not found at $REPO_PATH"
    exit 1
  fi
  download_cli_binary "$REPO_PATH/local/$BINARY_NAME"
  exit 0
fi

# Full install: download to /tmp and exec
DEST="/tmp/${BINARY_NAME}"
download_cli_binary "$DEST"
exec "$DEST" install "$@"
