#!/usr/bin/env bash
#
# Shared functions for jacks-nix scripts.
# Source this file, do not execute it directly.

# --- Pre-flight fixes (macOS) ---
# Resolves known issues that prevent darwin-rebuild from succeeding.
# Safe to call multiple times (idempotent).
darwin_preflight() {
  # nix-darwin manages /etc/{bashrc,zshrc,...} via symlinks to /etc/static/.
  # If macOS restores the originals (e.g. after a system update), darwin-rebuild
  # fails with "Unexpected files in /etc". Move non-symlink copies out of the way.
  for f in /etc/bashrc /etc/zshrc /etc/zshenv /etc/zprofile /etc/nix/nix.conf; do
    if [[ -e "$f" && ! -L "$f" ]]; then
      echo "⚠️  Moving $f to ${f}.before-nix-darwin (nix-darwin manages this file)"
      sudo mv "$f" "${f}.before-nix-darwin"
    fi
  done

  # home-manager >= 25.11 copies apps instead of symlinking them (copyApps).
  # If the old linkApps symlink still exists, rsync fails with permission errors.
  local hm_apps="$HOME/Applications/Home Manager Apps"
  if [[ -L "$hm_apps" ]]; then
    echo "⚠️  Removing old Home Manager Apps symlink (will be replaced by copied apps)"
    rm "$hm_apps"
  fi
}
