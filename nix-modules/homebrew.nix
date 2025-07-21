{ config, pkgs, lib, ... }:
{
  config = lib.mkIf (config.jacks-nix.enableHomebrew && pkgs.stdenv.isDarwin) {
    # Set up homebrew paths in user environment
    home.sessionPath = [
      "/opt/homebrew/bin"
      "/opt/homebrew/sbin"
    ];

    # Set up homebrew environment variables for user session
    home.sessionVariables = {
      HOMEBREW_PREFIX = "/opt/homebrew";
      HOMEBREW_CELLAR = "/opt/homebrew/Cellar";
      HOMEBREW_REPOSITORY = "/opt/homebrew";
    };

    # Add homebrew initialization to zsh if zsh is enabled
    programs.zsh = lib.mkIf config.jacks-nix.enableZsh {
      initContent = ''
        # Initialize Homebrew
        if [[ -f "/opt/homebrew/bin/brew" ]]; then
          eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
      '';
    };
  };
}
