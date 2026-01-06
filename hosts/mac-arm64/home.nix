{ pkgs, config, ... }:
{
  # Set the state version for Home Manager
  # This is required to ensure configuration stability across updates.
  home.stateVersion = "23.11";

  # Set the username from shared config
  home.username = config.jacks-nix.username;
  home.homeDirectory = "/Users/${config.jacks-nix.username}";

  imports = [
    ../../nix-modules
  ];

  #########################################################################
  # Mac-specific packages
  #########################################################################
  home.packages = with pkgs; [
    # Add any Mac-specific packages here
    # e.g., iterm2 (if available in nixpkgs)
  ];

  #########################################################################
  # Mac-specific configurations
  #########################################################################
  jacks-nix = {
    enableHomebrew = true;

    # Enable programming language tools by default on macOS development machines
    enableNode = true;
    enableJava = true;
    enableRuby = true;
    enableBun = true;
    enableAsdf = true;
  };
}
