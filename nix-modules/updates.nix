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

    # Update the check timestamp
    mkdir -p $(dirname "$check_file") # Ensure `local` dir is present.
    echo "$current_time" > "$check_file"

    # Change to config repo directory
    if [[ ! -d "$config_repo" ]]; then
      exit 0
    fi

    (
        cd "$config_repo" || exit 0

        # Fetch the `latest` tag from origin without merging
        git fetch origin tag latest --force >/dev/null 2>&1 || exit 0

        # Check if there are updates available
        local_commit=$(git rev-parse HEAD 2>/dev/null)
        remote_commit=$(git rev-parse "tags/latest" 2>/dev/null)

        if [[ -n "$remote_commit" ]]; then
          export GIT_PAGER=/bin/cat
          commits_to_pull=$(git log HEAD..tags/latest 2>/dev/null)

          if [[ -n "$commits_to_pull" ]]; then
              echo ""
              echo "🔄 Updates available for your Nix configuration!"
              echo ""

              # Show current local commit info
              echo "📍 Current local commit:"
              git log -1 --format="   %C(yellow)%h%C(reset) - %C(green)%ad%C(reset) - %s %C(dim)(%an)%C(reset)" --date=format:'%Y-%m-%d %H:%M' HEAD 2>/dev/null
              echo ""

              # Show commits that will be pulled
              echo "📥 New commits available:"
              git log --format="   %C(yellow)%h%C(reset) - %C(green)%ad%C(reset) - %s %C(dim)(%an)%C(reset)" --date=format:'%Y-%m-%d %H:%M' HEAD..tags/latest 2>/dev/null
              echo ""

              # Prompt user
              echo -n "Would you like to update now? (y/N): "
              read -n 1 -r response
              echo
              if [[ "$response" =~ ^[Yy]$ ]]; then
                echo "🚀 Updating configuration..."
                jacks-nix-update
              else
                echo "⏭️  Update skipped. Run 'update' manually when ready."
              fi
              echo ""
          fi
        fi
    )
  '';

  # A script to pull changes and apply the Nix configuration.
  updater = let
    updateCommand = if pkgs.stdenv.isDarwin
      then "sudo darwin-rebuild switch --flake \"${config.jacks-nix.configRepoPath}#mac-arm64\""
      else "home-manager switch --flake \"${config.jacks-nix.configRepoPath}#linux-x64\"";
  in pkgs.writeShellScriptBin "jacks-nix-update" ''
    set -euo pipefail

    (
      cd "${config.jacks-nix.configRepoPath}";
      echo "Fetching and checking out the `latest` tag from origin"
      git fetch origin tag latest --force
      git -c advice.detachedHead=false checkout tags/latest

      echo "Switching to latest nix flake configuration"
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
