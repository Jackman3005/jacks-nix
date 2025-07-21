{ pkgs, ... }:
{
  # Set the state version for Home Manager
  # This is required to ensure configuration stability across updates.
  home.stateVersion = "23.11";

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
  # Add any Mac-specific home-manager settings here
  # For example, different shell aliases or environment variables
}
