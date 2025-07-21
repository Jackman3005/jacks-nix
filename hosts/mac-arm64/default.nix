{ inputs, ... }:
let
  # Import the shared configuration to get username and other settings
  sharedConfig = import ../../config;
  username = sharedConfig.jacks-nix.user.username;
in
{
  # Import Home Manager configuration
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  # Set system-specific options for macOS
  system.stateVersion = 4;

  # Enable declarative nix.conf
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Fix GID mismatch for nixbld group
  ids.gids.nixbld = 350;

  # Create the user account
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
    inputs.nixvim.homeManagerModules.default
  ];
}
