{ lib, ... }:
{
  options.jacks-nix = {
    configRepoPath = lib.mkOption {
      type = lib.types.str;
      description = "Path to where this (jacks-nix) git repository will be stored.";
    };

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
    enableHomebrew = lib.mkEnableOption "Homebrew configuration (macOS only)";

    # Programming language support
    enablePython = lib.mkEnableOption "Python development tools (pyenv)";
    enableNode = lib.mkEnableOption "Node.js development tools (nvm)";
    enableJava = lib.mkEnableOption "Java development tools (SDKMAN)";
    enableRuby = lib.mkEnableOption "Ruby development tools";
    enableBun = lib.mkEnableOption "Bun JavaScript runtime";
    enableAsdf = lib.mkEnableOption "ASDF version manager";
  };
}
