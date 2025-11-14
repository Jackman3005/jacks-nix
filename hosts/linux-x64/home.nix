{ pkgs, config, ... }:
{
  # Set the state version for Home Manager
  home.stateVersion = "23.11";

  # Set the username from shared config
  home.username = config.jacks-nix.username;
  # Root user has a special home directory on Linux
  home.homeDirectory = if config.jacks-nix.username == "root"
    then "/root"
    else "/home/${config.jacks-nix.username}";

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
