{ config, pkgs, lib, ... }:

let
  # A script that will be run on shell startup to check for updates.
  updateChecker = pkgs.writeShellScriptBin "jacks-nix-update-check" ''
    #!${pkgs.zsh}/bin/zsh

    local config_repo="${config.jacks-nix.configRepoPath}"
    local check_file="$config_repo/local/last-update-check-timestamp.txt"
    local current_time=$(date +%s)

    # Check if we should run the update check (once per day max)
    if [[ -f "$check_file" ]]; then
      local last_check=$(cat "$check_file" 2>/dev/null || echo "0")
      local time_diff=$((current_time - last_check))
      # 86400 seconds = 24 hours
      if [[ $time_diff -lt 86400 ]]; then
        exit 0
      fi
    fi

    # Update the check timestamp
    echo "$current_time" > "$check_file"

    # Change to config repo directory
    if [[ ! -d "$config_repo" ]]; then
      exit 0
    fi

    cd "$config_repo" || exit 0

    # Fetch remote changes without merging
    git fetch origin >/dev/null 2>&1 || exit 0

    # Get current branch
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

    # Check if there are updates available
    local local_commit=$(git rev-parse HEAD 2>/dev/null)
    local remote_commit=$(git rev-parse "origin/$current_branch" 2>/dev/null)

    if [[ "$local_commit" != "$remote_commit" ]] && [[ -n "$remote_commit" ]]; then
      echo ""
      echo "🔄 Updates available for your Nix configuration!"
      echo ""

      # Show current local commit info
      echo "📍 Current local commit:"
      git log -1 --format="   %C(yellow)%h%C(reset) - %C(green)%ad%C(reset) - %s %C(dim)(%an)%C(reset)" --date=format:'%Y-%m-%d %H:%M' HEAD 2>/dev/null
      echo ""

      # Show commits that will be pulled
      echo "📥 New commits available:"
      git log --format="   %C(yellow)%h%C(reset) - %C(green)%ad%C(reset) - %s %C(dim)(%an)%C(reset)" --date=format:'%Y-%m-%d %H:%M' HEAD..origin/$current_branch 2>/dev/null
      echo ""

      # Prompt user
      echo -n "Would you like to update now? (y/N): "
      read -n 1 -r response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "🚀 Updating configuration..."
        jacks-nix-update
      else
        echo "⏭️  Update skipped. Run 'update' manually when ready."
      fi
      echo ""
    fi
  '';

  # A script to pull changes and apply the Nix configuration.
  updater = let
    updateCommand = if pkgs.stdenv.isDarwin
      then "sudo darwin-rebuild switch --flake \"${config.jacks-nix.configRepoPath}#mac-arm64\""
      else "home-manager switch --flake \"${config.jacks-nix.configRepoPath}#linux-x64\"";
  in pkgs.writeShellScriptBin "jacks-nix-update" ''
    #!${pkgs.zsh}/bin/zsh
    (
      cd "${config.jacks-nix.configRepoPath}" && git pull && ${updateCommand}
    ) && exec zsh
  '';

  # A script to update the flake lock file and commit the changes.
  upgrader = pkgs.writeShellScriptBin "jacks-nix-upgrade" ''
    #!${pkgs.zsh}/bin/zsh
    (
        cd "${config.jacks-nix.configRepoPath}"
        nix flake update
        if [ $? -eq 0 ]; then
          git add flake.lock
          git commit -m "chore: upgrade nix flake packages $(date +'%Y-%m-%d')"
          git push
        else
          echo 'Flake update failed, no commit made'
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
    ];

    home.shellAliases = {
      # Create simpler aliases for our update scripts
      update = "jacks-nix-update";
      upgrade = "jacks-nix-upgrade";
    };
  };
}
