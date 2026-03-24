#!/usr/bin/env bash
#
# Applies the nix configuration for the current OS.
#
# This script lives in the repo so that pre-flight fixes are always
# picked up from the version being installed, not the currently active
# generation. `jacks-nix-update` delegates here after checking out the
# latest tag.
#
# Usage: ./switch.sh [config_repo_path] [--skip-config]
#   --skip-config: skip load_config (caller already did it)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_REPO="${1:-$(dirname "$SCRIPT_DIR")}"
SKIP_CONFIG=false
for arg in "$@"; do
  [[ "$arg" == "--skip-config" ]] && SKIP_CONFIG=true
done

source "$SCRIPT_DIR/lib.sh"

# Load config unless caller already did it
if [[ "$SKIP_CONFIG" == "false" ]]; then
  load_config "$CONFIG_REPO" "update"
fi

case "$(uname -s)" in
  Darwin)
    darwin_preflight

    # Collect ALL JACKS_NIX_* env vars to pass through sudo.
    # Uses an array to preserve values with spaces (e.g. "Jack Coy").
    local_sudo_env=()
    while IFS='=' read -r key value; do
      local_sudo_env+=("$key=$value")
    done < <(env | grep '^JACKS_NIX_')

    sudo env "${local_sudo_env[@]}" /nix/var/nix/profiles/system/sw/bin/darwin-rebuild switch --impure --flake "${CONFIG_REPO}#mac-arm64"
    ;;
  Linux)
    home-manager switch --impure --flake "${CONFIG_REPO}#linux-x64"
    ;;
  *)
    echo "❌ Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

# Save config only after successful switch
save_config "$CONFIG_REPO"
