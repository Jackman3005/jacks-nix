{ pkgs, ... }:
{
  # Set the state version for Home Manager
  home.stateVersion = "23.11";

  imports = [
    ../../nix-modules
  ];

  #########################################################################
  # Ubuntu-specific packages
  #########################################################################
  home.packages = with pkgs; [
    # Add any Ubuntu/Linux-specific packages here
    # e.g., gnome-tweaks (if using GNOME)
  ];

  #########################################################################
  # Ubuntu-specific configurations
  #########################################################################
  # Add any Ubuntu-specific home-manager settings here
  # For example, different shell aliases or environment variables
}
