{ config, pkgs, lib, ... }:

let
  configRepoPath = config.jacks-nix.configRepoPath;

  # Shared script to display changelog between two versions
  # Usage: jacks-nix-changelog-show <from_version> <to_version> [--from-remote]
  # --from-remote: fetch changelogs from tags/latest instead of local files
  changelogDisplay = pkgs.writeShellScriptBin "jacks-nix-changelog-show" ''
    set -euo pipefail

    config_repo="${configRepoPath}"
    from_version="''${1:-0}"
    to_version="''${2:-0}"
    from_remote="''${3:-}"

    if [[ "$from_version" -ge "$to_version" ]]; then
      exit 0
    fi

    from_date=$(git -C "$config_repo" log -1 --format="%ad" --date=short HEAD 2>/dev/null || echo "unknown")
    to_date=$(git -C "$config_repo" log -1 --format="%ad" --date=short tags/latest 2>/dev/null || echo "unknown")

    highest_importance="minor"
    importance_order="minor fix feature breaking security"
    all_package_upgrades=""
    all_package_added=""
    all_package_removed=""
    all_manual_commits=""
    all_security_notes=""
    all_breaking_changes=""
    all_summaries=""

    for v in $(seq $((from_version + 1)) $to_version); do
      if [[ "$from_remote" == "--from-remote" ]]; then
        changelog=$(git -C "$config_repo" show "tags/latest:changelogs/''${v}.json" 2>/dev/null) || continue
      else
        changelog=$(cat "$config_repo/changelogs/''${v}.json" 2>/dev/null) || continue
      fi

      importance=$(echo "$changelog" | ${pkgs.jq}/bin/jq -r '.importance // "minor"')
      for imp in $importance_order; do
        if [[ "$imp" == "$importance" ]]; then
          highest_importance="$importance"
        fi
        if [[ "$imp" == "$highest_importance" ]]; then
          break
        fi
      done

      # Use tab-separated format for reliable parsing: name\tfrom\tto
      upgrades=$(echo "$changelog" | ${pkgs.jq}/bin/jq -r '.package_changes.upgraded[]? | "\(.name)\t\(.from)\t\(.to)"' 2>/dev/null || true)
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
    echo "🔄 Changes in jacks-nix"
    echo ""
    echo "   From: v$from_version ($from_date)"
    echo "   To:   v$to_version ($to_date)"
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

    # Combine package upgrades: if same package upgraded multiple times,
    # show first "from" version to last "to" version (e.g., 1.0→1.1→1.2 becomes 1.0→1.2)
    # Input format is tab-separated: name\tfrom\tto
    all_package_upgrades=$(echo "$all_package_upgrades" | grep -v '^$' | ${pkgs.gawk}/bin/awk -F'\t' '
      NF == 3 {
        pkg = $1
        from = $2
        to = $3
        if (!(pkg in first_from)) first_from[pkg] = from
        last_to[pkg] = to
      }
      END {
        for (pkg in last_to) {
          if (first_from[pkg] != last_to[pkg]) {
            print pkg ": " first_from[pkg] " → " last_to[pkg]
          }
        }
      }
    ' | sort || true)
    upgrade_count=$(echo "$all_package_upgrades" | grep -c . || echo "0")

    if [[ -n "$all_package_upgrades" && "$upgrade_count" -gt 0 ]]; then
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
  '';

  # A script that will be run on shell startup to check for updates.
  updateChecker = pkgs.writeShellScriptBin "jacks-nix-update-check" ''
    set -euo pipefail

    config_repo="${configRepoPath}"
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

        if [[ "$local_version" -ge "$remote_version" ]]; then
          exit 0
        fi

        # Display the changelog using the shared script
        jacks-nix-changelog-show "$local_version" "$remote_version" --from-remote

        echo -n "Would you like to update now? (y/N): "
        read -n 1 -r response < /dev/tty
        echo
        if [[ "$response" =~ ^[Yy]$ ]]; then
          echo "🚀 Updating configuration..."
          jacks-nix-update --no-changelog
        else
          echo "⏭️  Update skipped. Run 'update' manually when ready."
        fi
        echo ""
    )
  '';

  # A script to pull changes and apply the Nix configuration.
  updater = let
    updateCommand = if pkgs.stdenv.isDarwin
      then "sudo darwin-rebuild switch --flake \"${configRepoPath}#mac-arm64\""
      else "home-manager switch --flake \"${configRepoPath}#linux-x64\"";
  in pkgs.writeShellScriptBin "jacks-nix-update" ''
    set -euo pipefail

    config_repo="${configRepoPath}"
    show_changelog="true"
    applied_version_file="$config_repo/local/applied-version.txt"

    # Parse arguments
    for arg in "$@"; do
      case $arg in
        --no-changelog)
          show_changelog="false"
          ;;
      esac
    done

    ${lib.optionalString pkgs.stdenv.isDarwin ''
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    ''}

    (
      cd "$config_repo"
      LOG_FILE="$config_repo/local/update.log"
      mkdir -p "$(dirname "$LOG_FILE")"
      rm "$LOG_FILE" 2> /dev/null || true
      echo "\n\n--- update log: %s ---\n" "$(date)" >> "$LOG_FILE"

      echo "🌎 Fetching the 'latest' tag from origin..."
      git fetch origin tag latest --force >> "$LOG_FILE" 2>&1

      local_head=$(git rev-parse HEAD 2>> "$LOG_FILE")
      latest_tag=$(git rev-parse tags/latest 2>> "$LOG_FILE")

      local_version=$(cat "$config_repo/VERSION" 2>/dev/null || echo "0")
      remote_version=$(git show tags/latest:VERSION 2>/dev/null || echo "0")
      applied_version=$(cat "$applied_version_file" 2>/dev/null || echo "0")

      # Determine what action to take
      needs_git_update="false"
      needs_config_switch="false"

      if [[ "$local_head" != "$latest_tag" ]]; then
        needs_git_update="true"
        needs_config_switch="true"
      elif [[ "$applied_version" != "$local_version" ]]; then
        needs_config_switch="true"
      fi

      if [[ "$needs_git_update" == "false" && "$needs_config_switch" == "false" ]]; then
        echo "✅ You are already running the latest configuration (v$local_version)."
        exit 0
      fi

      # Show changelog if there are version changes and not suppressed
      if [[ "$show_changelog" == "true" ]]; then
        if [[ "$needs_git_update" == "true" && "$local_version" -lt "$remote_version" ]]; then
          jacks-nix-changelog-show "$local_version" "$remote_version" --from-remote
          echo -n "Continue with update? (Y/n): "
          read -n 1 -r response < /dev/tty
          echo
          if [[ "$response" =~ ^[Nn]$ ]]; then
            echo "⏭️  Update cancelled."
            exit 0
          fi
        elif [[ "$needs_config_switch" == "true" && "$applied_version" -lt "$local_version" ]]; then
          echo ""
          echo "🔄 Configuration changes detected but not yet applied."
          echo ""
          echo "   Applied: v$applied_version"
          echo "   Current: v$local_version"
          echo ""
          jacks-nix-changelog-show "$applied_version" "$local_version"
          echo -n "Apply configuration now? (Y/n): "
          read -n 1 -r response < /dev/tty
          echo
          if [[ "$response" =~ ^[Nn]$ ]]; then
            echo "⏭️  Configuration switch cancelled."
            exit 0
          fi
        fi
      fi

      # Checkout latest if needed
      if [[ "$needs_git_update" == "true" ]]; then
        echo "📥 Checking out latest tag..."
        git -c advice.detachedHead=false checkout tags/latest

        echo "🧹 Cleaning up unused nix packages and derivations..."

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
      fi

      echo "⏭️  Switching to nix flake configuration..."
      if ${updateCommand}; then
        # Record the successfully applied version
        current_version=$(cat "$config_repo/VERSION" 2>/dev/null || echo "0")
        echo "$current_version" > "$applied_version_file"
        echo "✅ Successfully applied configuration v$current_version"
      else
        echo "❌ Configuration switch failed"
        exit 1
      fi
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
      changelogDisplay
      updateChecker
      updater
      upgrader
      nvd
      gawk
    ];

    home.shellAliases = {
      # Create simpler aliases for our update scripts
      update = "jacks-nix-update";
      upgrade = "jacks-nix-upgrade";
    };
  };
}
