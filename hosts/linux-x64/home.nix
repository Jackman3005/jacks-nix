{ pkgs, config, inputs, ... }:
{
  # Set the state version for Home Manager
  home.stateVersion = "23.11";

  # Set the username from shared config
  home.username = config.jacks-nix.user.username;
  home.homeDirectory = "/home/${config.jacks-nix.user.username}";

  imports = [
    inputs.nixvim.homeManagerModules.nixvim
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
