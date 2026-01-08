{ config, pkgs, lib, ... }:

let
  configRepoPath = config.jacks-nix.configRepoPath;

  # ANSI color codes
  colors = ''
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m' # No Color
  '';

  # Helper to get explicitly declared packages (for highlighting "interesting" upgrades)
  declaredPackagesHelper = pkgs.writeShellScriptBin "jacks-nix-declared-packages" ''
    set -euo pipefail

    config_repo="${configRepoPath}"
    cache_dir="$HOME/.cache/jacks-nix"
    cache_file="$cache_dir/declared-packages.txt"

    # Check if cache exists and is less than 24 hours old
    if [[ -f "$cache_file" ]]; then
      cache_age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
      if [[ $cache_age -lt 86400 ]]; then
        cat "$cache_file"
        exit 0
      fi
    fi

    mkdir -p "$cache_dir"

    # Determine the flake output based on OS
    if [[ "$(uname -s)" == "Darwin" ]]; then
      flake_attr="darwinConfigurations.mac-arm64.config.home-manager.users.$(whoami).home.packages"
    else
      flake_attr="homeConfigurations.linux-x64.config.home.packages"
    fi

    # Get explicitly declared packages via nix eval
    packages=$(cd "$config_repo" && nix eval --json ".#$flake_attr" \
      --apply 'pkgs: map (p: p.pname or p.name or "unknown") pkgs' 2>/dev/null || echo "[]")

    # Filter out internal packages and write to cache
    echo "$packages" | ${pkgs.jq}/bin/jq -r '.[]' 2>/dev/null | \
      grep -v -E '^(hm-|home-configuration|session-vars|jacks-nix-|man-db|nix-zsh)' | \
      sort -u > "$cache_file"

    cat "$cache_file"
  '';

  # Main changelog display script
  # Usage:
  #   changelog [--full]           Compare applied version to latest
  #   changelog 297 [--full]       Compare applied version to v297
  #   changelog 290:297 [--full]   Compare v290 to v297
  changelogDisplay = pkgs.writeShellScriptBin "jacks-nix-changelog" ''
    set -euo pipefail

    ${colors}

    config_repo="${configRepoPath}"
    full_mode="false"
    from_version=""
    to_version=""

    # Parse arguments
    for arg in "$@"; do
      case $arg in
        --full)
          full_mode="true"
          ;;
        *:*)
          # Colon-separated range (e.g., 290:297)
          from_version="''${arg%%:*}"
          to_version="''${arg##*:}"
          ;;
        *)
          # Single version number
          if [[ -z "$to_version" ]]; then
            to_version="$arg"
          fi
          ;;
      esac
    done

    # Resolve defaults
    applied_version=$(cat "$config_repo/local/applied-version.txt" 2>/dev/null || cat "$config_repo/VERSION" 2>/dev/null || echo "0")

    # If no from_version, use applied version
    from_version="''${from_version:-$applied_version}"

    # If no to_version, fetch and use latest
    if [[ -z "$to_version" ]]; then
      git -C "$config_repo" fetch origin tag latest --force >/dev/null 2>&1 || true
      to_version=$(git -C "$config_repo" show tags/latest:VERSION 2>/dev/null || cat "$config_repo/VERSION" 2>/dev/null || echo "0")
    fi

    if [[ "$from_version" -ge "$to_version" ]]; then
      echo -e "''${GREEN}✅ You are up to date (v$from_version)''${NC}"
      exit 0
    fi

    # Get dates from changelog timestamps
    get_changelog_date() {
      local ver="$1"
      local ts=""
      if [[ -f "$config_repo/changelogs/''${ver}.json" ]]; then
        ts=$(${pkgs.jq}/bin/jq -r '.timestamp // empty' "$config_repo/changelogs/''${ver}.json" 2>/dev/null)
      else
        ts=$(git -C "$config_repo" show "tags/latest:changelogs/''${ver}.json" 2>/dev/null | ${pkgs.jq}/bin/jq -r '.timestamp // empty' 2>/dev/null)
      fi
      # Extract just the date part (YYYY-MM-DD) from ISO timestamp
      echo "''${ts:0:10}"
    }

    from_date=$(get_changelog_date "$from_version")
    to_date=$(get_changelog_date "$to_version")
    from_date="''${from_date:-unknown}"
    to_date="''${to_date:-unknown}"

    # Calculate days difference
    days_diff=0
    if [[ "$from_date" != "unknown" && "$to_date" != "unknown" && "$from_date" != "" && "$to_date" != "" ]]; then
      from_epoch=$(date -j -f "%Y-%m-%d" "$from_date" "+%s" 2>/dev/null || date -d "$from_date" "+%s" 2>/dev/null || echo "0")
      to_epoch=$(date -j -f "%Y-%m-%d" "$to_date" "+%s" 2>/dev/null || date -d "$to_date" "+%s" 2>/dev/null || echo "0")
      if [[ "$from_epoch" -gt 0 && "$to_epoch" -gt 0 ]]; then
        days_diff=$(( (to_epoch - from_epoch) / 86400 ))
      fi
    fi

    # Load declared packages for highlighting
    declared_packages=""
    if [[ -x "$(command -v jacks-nix-declared-packages)" ]]; then
      declared_packages=$(jacks-nix-declared-packages 2>/dev/null || true)
    fi

    # --- SIZE COMPARISON HELPERS ---
    format_size() {
      local bytes="$1"
      if [[ -z "$bytes" || "$bytes" == "null" ]]; then
        echo "unknown"
      elif [[ "$bytes" -ge 1073741824 ]]; then
        printf "%.1f GiB" "$(echo "$bytes / 1073741824" | ${pkgs.bc}/bin/bc -l)"
      elif [[ "$bytes" -ge 1048576 ]]; then
        printf "%d MiB" "$((bytes / 1048576))"
      else
        printf "%d KiB" "$((bytes / 1024))"
      fi
    }

    get_changelog_sizes() {
      local ver="$1"
      local changelog=""
      if [[ -f "$config_repo/changelogs/''${ver}.json" ]]; then
        changelog=$(cat "$config_repo/changelogs/''${ver}.json" 2>/dev/null)
      else
        changelog=$(git -C "$config_repo" show "tags/latest:changelogs/''${ver}.json" 2>/dev/null) || true
      fi

      if [[ -n "$changelog" ]]; then
        echo "$changelog" | ${pkgs.jq}/bin/jq -r '.closure_sizes // empty'
      fi
    }

    all_package_upgrades=""
    all_package_added=""
    all_package_removed=""
    all_manual_commits=""

    for v in $(seq $((from_version + 1)) $to_version); do
      # Try local file first, fall back to remote tag (handles gaps gracefully)
      if [[ -f "$config_repo/changelogs/''${v}.json" ]]; then
        changelog=$(cat "$config_repo/changelogs/''${v}.json" 2>/dev/null) || continue
      else
        changelog=$(git -C "$config_repo" show "tags/latest:changelogs/''${v}.json" 2>/dev/null) || continue
      fi

      upgrades=$(echo "$changelog" | ${pkgs.jq}/bin/jq -r '.package_changes.upgraded[]? | "\(.name)\t\(.from)\t\(.to)"' 2>/dev/null || true)
      if [[ -n "$upgrades" ]]; then
        all_package_upgrades="$all_package_upgrades$upgrades"$'\n'
      fi

      # Handle both old format (strings) and new format ({name, version} objects)
      added=$(echo "$changelog" | ${pkgs.jq}/bin/jq -r '.package_changes.added[]? | if type == "object" then "\(.name)\t\(.version)" else . end' 2>/dev/null || true)
      if [[ -n "$added" ]]; then
        all_package_added="$all_package_added$added"$'\n'
      fi

      removed=$(echo "$changelog" | ${pkgs.jq}/bin/jq -r '.package_changes.removed[]? | if type == "object" then "\(.name)\t\(.version)" else . end' 2>/dev/null || true)
      if [[ -n "$removed" ]]; then
        all_package_removed="$all_package_removed$removed"$'\n'
      fi

      manual=$(echo "$changelog" | ${pkgs.jq}/bin/jq -r '.manual_commits[]? | "\(.message)"' 2>/dev/null || true)
      if [[ -n "$manual" ]]; then
        all_manual_commits="$all_manual_commits$manual"$'\n'
      fi
    done

    # Aggregate package upgrades (combine multi-step version jumps)
    all_package_upgrades=$(echo "$all_package_upgrades" | grep -v '^$' | ${pkgs.gawk}/bin/gawk -F'\t' '
      NF == 3 {
        pkg = $1; from = $2; to = $3
        if (!(pkg in first_from)) first_from[pkg] = from
        last_to[pkg] = to
      }
      END {
        for (pkg in last_to) {
          if (first_from[pkg] != last_to[pkg]) {
            print pkg "\t" first_from[pkg] "\t" last_to[pkg]
          }
        }
      }
    ' | sort || true)

    total_upgrade_count=$(echo "$all_package_upgrades" | grep -c . || echo "0")

    # Separate key upgrades (declared packages) from dependency upgrades
    key_upgrades=""
    dep_upgrades=""
    if [[ -n "$declared_packages" && -n "$all_package_upgrades" ]]; then
      while IFS=$'\t' read -r pkg from to; do
        [[ -z "$pkg" ]] && continue
        if echo "$declared_packages" | grep -qx "$pkg"; then
          key_upgrades="$key_upgrades$pkg\t$from\t$to"$'\n'
        else
          dep_upgrades="$dep_upgrades$pkg\t$from\t$to"$'\n'
        fi
      done <<< "$all_package_upgrades"
    else
      dep_upgrades="$all_package_upgrades"
    fi

    key_count=$(echo "$key_upgrades" | grep -c . || echo "0")
    dep_count=$(echo "$dep_upgrades" | grep -c . || echo "0")

    # Deduplicate commits and count
    unique_commits=$(echo "$all_manual_commits" | grep -v '^$' | sort -u || true)
    commit_count=$(echo "$unique_commits" | grep -c . || echo "0")

    # --- SIZE COMPARISON ---
    from_sizes=$(get_changelog_sizes "$from_version")
    to_sizes=$(get_changelog_sizes "$to_version")

    from_linux=$(echo "$from_sizes" | ${pkgs.jq}/bin/jq -r '.linux_x64_bytes // empty' 2>/dev/null || true)
    to_linux=$(echo "$to_sizes" | ${pkgs.jq}/bin/jq -r '.linux_x64_bytes // empty' 2>/dev/null || true)
    from_mac=$(echo "$from_sizes" | ${pkgs.jq}/bin/jq -r '.mac_arm64_bytes // empty' 2>/dev/null || true)
    to_mac=$(echo "$to_sizes" | ${pkgs.jq}/bin/jq -r '.mac_arm64_bytes // empty' 2>/dev/null || true)

    size_warning=""
    size_info=""

    check_size_increase() {
      local from="$1" to="$2" platform="$3"
      [[ -z "$from" || -z "$to" || "$from" == "null" || "$to" == "null" ]] && return

      local diff=$((to - from))
      local pct=0
      [[ "$from" -gt 0 ]] && pct=$((diff * 100 / from))

      local diff_mb=$((diff / 1048576))
      local threshold_mb=300
      local threshold_pct=15

      if [[ "$diff" -gt 0 ]]; then
        if [[ "$pct" -gt "$threshold_pct" ]] || [[ "$diff_mb" -gt "$threshold_mb" ]]; then
          size_warning="''${size_warning}''${RED}⚠️  Warning: ''${platform} size increased by ''${pct}% (+''${diff_mb} MiB)''${NC}\n"
        fi

        local from_fmt=$(format_size "$from")
        local to_fmt=$(format_size "$to")
        size_info="''${size_info}   ''${platform}: ''${from_fmt} → ''${to_fmt} (+''${diff_mb} MiB)\n"
      elif [[ "$diff" -lt 0 ]]; then
        local saved_mb=$(( (-diff) / 1048576 ))
        local from_fmt=$(format_size "$from")
        local to_fmt=$(format_size "$to")
        size_info="''${size_info}   ''${platform}: ''${from_fmt} → ''${to_fmt} (-''${saved_mb} MiB) ✨\n"
      fi
    }

    check_size_increase "$from_linux" "$to_linux" "Linux"
    check_size_increase "$from_mac" "$to_mac" "macOS"

    # --- OUTPUT ---
    output_content() {
      echo ""
      echo -e "''${CYAN}╭─────────────────────────────────────────────────────────────╮''${NC}"
      echo -e "''${CYAN}│''${NC}  ''${BOLD}🔄 jacks-nix updates available''${NC}                             ''${CYAN}│''${NC}"
      echo -e "''${CYAN}╰─────────────────────────────────────────────────────────────╯''${NC}"
      echo ""
      echo -e "   Current: ''${DIM}v$from_version ($from_date)''${NC}"
      if [[ "$days_diff" -gt 0 ]]; then
        echo -e "   Latest:  ''${GREEN}v$to_version ($to_date)''${NC}  ''${YELLOW}← $days_diff days newer''${NC}"
      else
        echo -e "   Latest:  ''${GREEN}v$to_version ($to_date)''${NC}"
      fi
      echo ""

      # Key upgrades (declared packages)
      if [[ -n "$key_upgrades" && "$key_count" -gt 0 ]]; then
        echo -e "''${GREEN}📦 Key Upgrades:''${NC}"
        if [[ "$full_mode" == "true" ]]; then
          echo "$key_upgrades" | grep -v '^$' | while IFS=$'\t' read -r pkg from to; do
            echo "   $pkg $from → $to"
          done
        else
          # Condensed: show up to 6, one per line for clarity
          echo "$key_upgrades" | grep -v '^$' | head -6 | while IFS=$'\t' read -r pkg from to; do
            printf "   %s %s → %s\n" "$pkg" "$from" "$to"
          done
          if [[ "$key_count" -gt 6 ]]; then
            remaining=$((key_count - 6))
            echo -e "   ''${DIM}... and $remaining more key packages''${NC}"
          fi
        fi
        if [[ "$dep_count" -gt 0 ]]; then
          echo -e "   ''${DIM}... and $dep_count dependency updates''${NC}"
        fi
        echo ""
      elif [[ "$total_upgrade_count" -gt 0 ]]; then
        echo -e "''${GREEN}📦 Package Upgrades:''${NC} $total_upgrade_count packages updated"
        if [[ "$full_mode" == "true" ]]; then
          echo "$all_package_upgrades" | grep -v '^$' | while IFS=$'\t' read -r pkg from to; do
            echo "   $pkg $from → $to"
          done
        fi
        echo ""
      fi

      # Size changes
      if [[ -n "$size_info" ]]; then
        echo -e "''${YELLOW}💾 Size Changes:''${NC}"
        echo -e "$size_info"
        if [[ -n "$size_warning" ]]; then
          echo -e "$size_warning"
        fi
      fi

      # Manual commits
      if [[ -n "$unique_commits" && "$commit_count" -gt 0 ]]; then
        echo -e "''${BLUE}📝 Recent Changes:''${NC}"
        if [[ "$full_mode" == "true" ]]; then
          echo "$unique_commits" | while read -r line; do
            [[ -n "$line" ]] && echo "   • $line"
          done
        else
          # Show up to 5 commits in condensed mode
          echo "$unique_commits" | head -5 | while read -r line; do
            [[ -n "$line" ]] && echo "   • $line"
          done
          if [[ "$commit_count" -gt 5 ]]; then
            remaining=$((commit_count - 5))
            echo -e "   ''${DIM}... and $remaining more commits''${NC}"
          fi
        fi
        echo ""
      fi

      # Full mode: show added/removed packages
      if [[ "$full_mode" == "true" ]]; then
        if [[ -n "$all_package_added" ]]; then
          added_list=$(echo "$all_package_added" | grep -v '^$' | sort -u)
          added_count=$(echo "$added_list" | grep -c . || echo "0")
          echo -e "''${GREEN}➕ Packages Added ($added_count):''${NC}"
          echo "$added_list" | while IFS=$'\t' read -r name version; do
            if [[ -n "$version" ]]; then
              echo "   $name $version"
            elif [[ -n "$name" ]]; then
              echo "   $name"
            fi
          done
          echo ""
        fi

        if [[ -n "$all_package_removed" ]]; then
          removed_list=$(echo "$all_package_removed" | grep -v '^$' | sort -u)
          removed_count=$(echo "$removed_list" | grep -c . || echo "0")
          echo -e "''${RED}➖ Packages Removed ($removed_count):''${NC}"
          echo "$removed_list" | while IFS=$'\t' read -r name version; do
            if [[ -n "$version" ]]; then
              echo "   $name $version"
            elif [[ -n "$name" ]]; then
              echo "   $name"
            fi
          done
          echo ""
        fi

      fi

      # Action hints (only in condensed mode)
      if [[ "$full_mode" != "true" ]]; then
        echo -e "''${DIM}Run: update           Apply changes now''${NC}"
        echo -e "''${DIM}     changelog --full View complete changelog''${NC}"
        echo ""
      fi
    }

    # Output: use pager for full mode, direct output for condensed
    if [[ "$full_mode" == "true" ]]; then
      if command -v bat &>/dev/null; then
        output_content | bat --style=plain --paging=always
      elif command -v less &>/dev/null; then
        output_content | less -R
      else
        output_content
      fi
    else
      output_content
    fi
  '';

  # A script that will be run on shell startup to check for updates.
  # Now non-blocking - just shows changelog and action hints
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

        # Display the condensed changelog (non-blocking)
        jacks-nix-changelog "$local_version:$remote_version"
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
          jacks-nix-changelog "$local_version:$remote_version"
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
          jacks-nix-changelog "$applied_version:$local_version"
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

        # Refresh the declared packages cache
        echo "📦 Refreshing package cache..."
        rm -f "$HOME/.cache/jacks-nix/declared-packages.txt" 2>/dev/null || true
        jacks-nix-declared-packages >/dev/null 2>&1 || true
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
      declaredPackagesHelper
      changelogDisplay
      updateChecker
      updater
      upgrader
      nvd
      gawk
      bc
    ];

    home.shellAliases = {
      # Create simpler aliases for our update scripts
      update = "jacks-nix-update";
      upgrade = "jacks-nix-upgrade";
      changelog = "jacks-nix-changelog";
    };
  };
}
