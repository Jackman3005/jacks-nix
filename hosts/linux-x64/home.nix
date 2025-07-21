{ pkgs, ... }:
{
  # Set the state version for Home Manager
  home.stateVersion = "23.11";

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
  # Add any Linux-specific home-manager settings here
  # For example, different shell aliases or environment variables
}
