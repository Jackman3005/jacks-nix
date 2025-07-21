{ pkgs, ... }:
let
  # Import the shared configuration to get username and other settings
  sharedConfig = import ../../config;
in
{
  # Set the state version for Home Manager
  # This is required to ensure configuration stability across updates.
  home.stateVersion = "23.11";

  # Set the username from shared config
  home.username = sharedConfig.jacks-nix.user.username;
  home.homeDirectory = "/Users/${sharedConfig.jacks-nix.user.username}";

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
  # Enable programming language tools by default on macOS
  jacks-nix = {
    enablePython = true;
    enableNode = true;
    enableJava = true;
    enableRuby = true;
    enableBun = true;
    enableAsdf = true;
  };
}
