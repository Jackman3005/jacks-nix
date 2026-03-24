#!/usr/bin/env bash
#
# Shared functions for jacks-nix scripts.
# Source this file, do not execute it directly.

# --- Pre-flight fixes (macOS) ---
# Resolves known issues that prevent darwin-rebuild from succeeding.
# Safe to call multiple times (idempotent).
darwin_preflight() {
  : # No pre-flight fixes needed at this time.
}
