{ lib, ... }:
{
  options.jacks-nix = {
    user = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Your full name for Git configuration.";
      };
      email = lib.mkOption {
        type = lib.types.str;
        description = "Your email address for Git configuration.";
      };
      username = lib.mkOption {
        type = lib.types.str;
        description = "Your system username.";
      };
    };

    enableGit = lib.mkEnableOption "Git configuration";
    enableZsh = lib.mkEnableOption "Zsh and Oh My Zsh configuration";
    enableNvim = lib.mkEnableOption "Neovim configuration with nixvim";
  };
}