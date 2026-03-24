#!/usr/bin/env bash
#
# Applies the nix configuration for the current OS.
#
# This script lives in the repo so that pre-flight fixes are always
# picked up from the version being installed, not the currently active
# generation. `jacks-nix-update` delegates here after checking out the
# latest tag.
#
# Usage: ./switch.sh [config_repo_path]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_REPO="${1:-$(dirname "$SCRIPT_DIR")}"

source "$SCRIPT_DIR/lib.sh"

case "$(uname -s)" in
  Darwin)
    darwin_preflight
    sudo /nix/var/nix/profiles/system/sw/bin/darwin-rebuild switch --flake "${CONFIG_REPO}#mac-arm64"
    ;;
  Linux)
    home-manager switch --flake "${CONFIG_REPO}#linux-x64"
    ;;
  *)
    echo "❌ Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac
