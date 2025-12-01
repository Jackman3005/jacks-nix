{ inputs, config, lib, pkgs, ... }:
let
  username = config.jacks-nix.username;
  nixbldGroupId = config.jacks-nix.mac.nixbldGroupId;
  nixbldUserId = config.jacks-nix.mac.nixbldUserId;
in
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  # Set system-specific options for macOS
  system.stateVersion = 4;

  # Enable declarative nix.conf
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Fix UID/GID mismatch issues for nixbld
  ids.uids.nixbld = nixbldUserId;
  ids.gids.nixbld = nixbldGroupId;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  # Home Manager configuration
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.${username} = import ./home.nix;

  # Backup existing files that would be overwritten
  home-manager.backupFileExtension = "backup";

  # Pass specialArgs down to home-manager
  home-manager.extraSpecialArgs = {
    inherit inputs;
  };

  # Import nixvim module for home-manager
  home-manager.sharedModules = [
    inputs.nixvim.homeModules.default
  ];

  # Set primary user for homebrew and other user-specific system settings
  system.primaryUser = lib.mkIf config.jacks-nix.enableHomebrew username;

  # Homebrew configuration (only enabled if enableHomebrew is true)
  homebrew = lib.mkIf config.jacks-nix.enableHomebrew {
    enable = true;

    # Automatically update homebrew and upgrade packages
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "none";
    };

    # Configure homebrew settings
    global = {
      brewfile = true;
      lockfiles = false;
    };

    # Add homebrew taps (repositories)
    taps = [
      "homebrew/services"
    ];

    # Install basic homebrew packages
    brews = [
      # Add any brew packages you want here
      # Example: "wget"
    ];

    # Install cask applications
    casks = [
      # Add any cask applications you want here
      # Example: "firefox"
    ];
  };
}
