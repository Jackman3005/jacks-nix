#!/usr/bin/env bash
#
# Bootstrap installer for jacks-nix.
# Downloads the CLI binary and delegates to `jacks-nix install`.
#
# Usage: curl -fsSL https://raw.githubusercontent.com/Jackman3005/jacks-nix/latest/bin/install.sh | bash

set -euo pipefail

BINARY_NAME="jacks-nix"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)  PLATFORM="darwin-arm64" ;;
  Linux-x86_64)  PLATFORM="linux-x64" ;;
  *)
    echo "Unsupported platform: $(uname -s)-$(uname -m)"
    exit 1
    ;;
esac

URL="https://github.com/Jackman3005/jacks-nix/releases/download/latest/${BINARY_NAME}-${PLATFORM}"
DEST="/tmp/${BINARY_NAME}"

echo "Downloading jacks-nix CLI..."
curl -fsSL "$URL" -o "$DEST"
chmod +x "$DEST"

exec "$DEST" install "$@"
