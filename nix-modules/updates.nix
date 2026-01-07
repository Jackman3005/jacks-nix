{ config, pkgs, lib, ... }:

let
  # A script that will be run on shell startup to check for updates.
  updateChecker = pkgs.writeShellScriptBin "jacks-nix-update-check" ''
    set -euo pipefail

    config_repo="${config.jacks-nix.configRepoPath}"
    check_file="$config_repo/local/last-update-check-timestamp.txt"
    current_time=$(date +%s)

    # Check if we should run the update check (once per day max)
    if [[ -f "$check_file" ]]; then
      last_check=$(cat "$check_file" 2>/dev/null || echo "0")
      time_diff=$((current_time - last_check))
      # 86400 seconds = 24 hours
      if [[ $time_diff -lt 86400 ]]; then
        exit 0
      fi
    fi

    mkdir -p "$(dirname "$check_file")"
    echo "$current_time" > "$check_file"

    # Change to config repo directory
    if [[ ! -d "$config_repo" ]]; then
      exit 0
    fi

    (
        cd "$config_repo" || exit 0

        git fetch origin tag latest --force >/dev/null 2>&1 || exit 0

        local_commit=$(git rev-parse HEAD 2>/dev/null)
        remote_commit=$(git rev-parse "tags/latest" 2>/dev/null)

        if [[ "$local_commit" == "$remote_commit" ]]; then
          exit 0
        fi

        local_version=$(cat "$config_repo/VERSION" 2>/dev/null || echo "0")
        remote_version=$(git show tags/latest:VERSION 2>/dev/null || echo "0")

        if [[ "$local_version" == "$remote_version" ]]; then
          exit 0
        fi

        local_date=$(git log -1 --format="%ad" --date=short HEAD 2>/dev/null || echo "unknown")
        remote_date=$(git log -1 --format="%ad" --date=short tags/latest 2>/dev/null || echo "unknown")

        highest_importance="minor"
        importance_order="minor fix feature breaking security"
        all_package_upgrades=""
        all_package_added=""
        all_package_removed=""
        all_manual_commits=""
        all_security_notes=""
        all_breaking_changes=""
        all_summaries=""

        for v in $(seq $((local_version + 1)) $remote_version); do
          changelog=$(git show "tags/latest:changelogs/''${v}.json" 2>/dev/null) || continue

          importance=$(echo "$changelog" | ${pkgs.jq}/bin/jq -r '.importance // "minor"')
          for imp in $importance_order; do
            if [[ "$imp" == "$importance" ]]; then
              highest_importance="$importance"
            fi
            if [[ "$imp" == "$highest_importance" ]]; then
              break
            fi
          done

          upgrades=$(echo "$changelog" | ${pkgs.jq}/bin/jq -r '.package_changes.upgraded[]? | "\(.name): \(.from) → \(.to)"' 2>/dev/null || true)
          if [[ -n "$upgrades" ]]; then
            all_package_upgrades="$all_package_upgrades$upgrades"$'\n'
          fi

          added=$(echo "$changelog" | ${pkgs.jq}/bin/jq -r '.package_changes.added[]?' 2>/dev/null || true)
          if [[ -n "$added" ]]; then
            all_package_added="$all_package_added$added"$'\n'
          fi

          removed=$(echo "$changelog" | ${pkgs.jq}/bin/jq -r '.package_changes.removed[]?' 2>/dev/null || true)
          if [[ -n "$removed" ]]; then
            all_package_removed="$all_package_removed$removed"$'\n'
          fi

          manual=$(echo "$changelog" | ${pkgs.jq}/bin/jq -r '.manual_commits[]? | "• \(.message)"' 2>/dev/null || true)
          if [[ -n "$manual" ]]; then
            all_manual_commits="$all_manual_commits$manual"$'\n'
          fi

          security=$(echo "$changelog" | ${pkgs.jq}/bin/jq -r '.security_notes[]?' 2>/dev/null || true)
          if [[ -n "$security" ]]; then
            all_security_notes="$all_security_notes$security"$'\n'
          fi

          breaking=$(echo "$changelog" | ${pkgs.jq}/bin/jq -r '.breaking_changes[]?' 2>/dev/null || true)
          if [[ -n "$breaking" ]]; then
            all_breaking_changes="$all_breaking_changes$breaking"$'\n'
          fi

          summary=$(echo "$changelog" | ${pkgs.jq}/bin/jq -r '.ai_summary // empty' 2>/dev/null || true)
          if [[ -n "$summary" ]]; then
            all_summaries="$all_summaries  v$v: $summary"$'\n'
          fi
        done

        echo ""
        echo "🔄 Updates available for jacks-nix!"
        echo ""
        echo "   Current: v$local_version ($local_date)"
        echo "   Latest:  v$remote_version ($remote_date)"
        echo ""

        case "$highest_importance" in
          security)
            echo "┌──────────────────────────────────────────────────────────────┐"
            echo "│  🚨 SECURITY UPDATE                                          │"
            echo "└──────────────────────────────────────────────────────────────┘"
            ;;
          breaking)
            echo "┌──────────────────────────────────────────────────────────────┐"
            echo "│  ⚠️  BREAKING CHANGES                                         │"
            echo "└──────────────────────────────────────────────────────────────┘"
            ;;
          feature)
            echo "┌──────────────────────────────────────────────────────────────┐"
            echo "│  ✨ NEW FEATURES                                              │"
            echo "└──────────────────────────────────────────────────────────────┘"
            ;;
          fix)
            echo "┌──────────────────────────────────────────────────────────────┐"
            echo "│  🔧 BUG FIXES                                                 │"
            echo "└──────────────────────────────────────────────────────────────┘"
            ;;
          *)
            echo "┌──────────────────────────────────────────────────────────────┐"
            echo "│  📦 MINOR UPDATES                                             │"
            echo "└──────────────────────────────────────────────────────────────┘"
            ;;
        esac
        echo ""

        if [[ -n "$all_security_notes" || -n "$all_breaking_changes" ]]; then
          echo "🚨 Important Changes:"
          if [[ -n "$all_security_notes" ]]; then
            echo "$all_security_notes" | while read -r line; do
              [[ -n "$line" ]] && echo "   [SECURITY] $line"
            done
          fi
          if [[ -n "$all_breaking_changes" ]]; then
            echo "$all_breaking_changes" | while read -r line; do
              [[ -n "$line" ]] && echo "   [BREAKING] $line"
            done
          fi
          echo ""
        fi

        if [[ -n "$all_summaries" ]]; then
          echo "📋 Update Summaries:"
          echo "$all_summaries"
          echo ""
        fi

        all_package_upgrades=$(echo "$all_package_upgrades" | sort -u | grep -v '^$' || true)
        upgrade_count=$(echo "$all_package_upgrades" | grep -c . || echo "0")

        if [[ -n "$all_package_upgrades" ]]; then
          echo "📦 Package Changes ($upgrade_count upgrades):"
          echo "$all_package_upgrades" | while read -r line; do
            [[ -n "$line" ]] && echo "   $line"
          done
          echo ""
        fi

        if [[ -n "$all_package_added" ]]; then
          echo "➕ Packages Added:"
          echo "$all_package_added" | sort -u | while read -r line; do
            [[ -n "$line" ]] && echo "   $line"
          done
          echo ""
        fi

        if [[ -n "$all_package_removed" ]]; then
          echo "➖ Packages Removed:"
          echo "$all_package_removed" | sort -u | while read -r line; do
            [[ -n "$line" ]] && echo "   $line"
          done
          echo ""
        fi

        if [[ -n "$all_manual_commits" ]]; then
          echo "🔧 Config Changes:"
          echo "$all_manual_commits" | sort -u | while read -r line; do
            [[ -n "$line" ]] && echo "   $line"
          done
          echo ""
        fi

        echo -n "Would you like to update now? (y/N): "
        read -n 1 -r response < /dev/tty
        echo
        if [[ "$response" =~ ^[Yy]$ ]]; then
          echo "🚀 Updating configuration..."
          jacks-nix-update
        else
          echo "⏭️  Update skipped. Run 'update' manually when ready."
        fi
        echo ""
    )
  '';

  # A script to pull changes and apply the Nix configuration.
  updater = let
    updateCommand = if pkgs.stdenv.isDarwin
      then "sudo darwin-rebuild switch --flake \"${config.jacks-nix.configRepoPath}#mac-arm64\""
      else "home-manager switch --flake \"${config.jacks-nix.configRepoPath}#linux-x64\"";
  in pkgs.writeShellScriptBin "jacks-nix-update" ''
    set -euo pipefail

    ${lib.optionalString pkgs.stdenv.isDarwin ''
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    ''}

    (
      cd "${config.jacks-nix.configRepoPath}";
      LOG_FILE="${config.jacks-nix.configRepoPath}/local/update.log"
      rm "$LOG_FILE" 2> /dev/null || true
      echo "\n\n--- update log: %s ---\n" "$(date)" >> "$LOG_FILE"

      echo "🌎 Fetching and checking out the 'latest' tag from origin"
      git fetch origin tag latest --force >> "$LOG_FILE" 2>&1

      local_head=$(git rev-parse HEAD 2>> "$LOG_FILE")
      latest_tag=$(git rev-parse tags/latest 2>> "$LOG_FILE")

      if [ "$local_head" == "$latest_tag" ]; then
          echo "🔄 You are already at the latest version."
          echo "   You can manually run \`${updateCommand}\` if you'd like, but there are no changes from git."
          exit 0
      fi

      git -c advice.detachedHead=false checkout tags/latest

      echo "🧹 Cleaning up unused nix packages and derivations..."
      echo "   Keeping only the new derivation and the one right before it..."

      # Remove any generations older than 30 days that are not active.
      if nix-collect-garbage --delete-older-than 30d >> "$LOG_FILE" 2>&1; then
        echo "✅ Successfully cleaned up old generations"
      else
        echo "⚠️  Warning: Could not clean up old generations (this is usually fine)"
      fi

      # Run garbage collection to free up disk space
      if nix-store --gc >> "$LOG_FILE" 2>&1; then
        echo "✅ Successfully performed garbage collection"
      else
        echo "⚠️  Warning: Could not perform garbage collection (this is usually fine)"
      fi

      echo "⏭️ Switching to latest nix flake configuration"
      ${updateCommand}
    ) && exec zsh
  '';

  # A script to update the flake lock file and commit the changes.
  upgrader = pkgs.writeShellScriptBin "jacks-nix-upgrade" ''
    set -euo pipefail

    (
        cd "${config.jacks-nix.configRepoPath}"

        echo "🔄 Running nix flake update..."
        nix flake update

        if [ $? -eq 0 ]; then
          echo "✅ Flake update completed successfully"

          # Check if there are actually any changes to flake.lock
          if git diff --quiet flake.lock; then
            echo "ℹ️  No changes to flake.lock - packages are already up to date"
            exit 0
          fi

          echo "📝 Changes detected in flake.lock, preparing to commit..."

          # Check if we can push to the repository
          if git push --dry-run >/dev/null 2>&1; then
            # Commit and push the changes
            echo "💾 Committing changes..."
            if git commit flake.lock -m "chore: upgrade nix flake packages $(date +'%Y-%m-%d')"; then
              echo "📤 Pushing changes to remote repository..."
              if git push; then
                echo "🎉 Successfully updated and pushed flake.lock!"
              else
                echo "❌ Failed to push changes to remote repository"
                echo "   The commit was made locally but could not be pushed"
                exit 1
              fi
            else
              echo "❌ Failed to commit changes"
              exit 1
            fi
          else
            echo
            echo "⚠️  No push permissions detected!"
            echo "    Skipping committing and pushing. You have unstaged changes!"
            echo "    Repo dir: $(cd \"${config.jacks-nix.configRepoPath}\" && pwd)"

          fi
        else
          echo "❌ Flake update failed, no changes made"
          exit 1
        fi
    )
  '';

in
{
  config = lib.mkIf config.jacks-nix.enableZsh {
    home.packages = with pkgs; [
      # Add update scripts to the user's PATH
      updateChecker
      updater
      upgrader
      nvd
    ];

    home.shellAliases = {
      # Create simpler aliases for our update scripts
      update = "jacks-nix-update";
      upgrade = "jacks-nix-upgrade";
    };
  };
}
