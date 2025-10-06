{ pkgs, config, ... }:
{
  # Set the state version for Home Manager
  home.stateVersion = "23.11";

  # Set the username from shared config
  home.username = config.jacks-nix.username;
  home.homeDirectory = "/home/${config.jacks-nix.username}";

  imports = [
    ../../nix-modules
  ];

  #########################################################################
  # Linux-specific packages
  #########################################################################
  home.packages = with pkgs; [
    # Add any Linux-specific packages here
    # e.g., gnome-tweaks (if using GNOME)
  ];

  #########################################################################
  # Linux-specific configurations
  #########################################################################
  jacks-nix = {
    enableHomebrew = false;
  };
}
