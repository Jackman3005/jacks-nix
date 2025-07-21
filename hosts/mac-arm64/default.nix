{ inputs, ... }:
{
  # Import Home Manager configuration
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  # Set system-specific options for macOS
  system.stateVersion = 4;

  # Enable declarative nix.conf
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.jack = import ./home.nix; # Point to home.nix

  # Pass nixvim to home-manager modules
  home-manager.extraSpecialArgs = {
    inherit (inputs) nixvim;
    system = "aarch64-darwin";
  };

  # Import nixvim module for home-manager
  home-manager.sharedModules = [
    inputs.nixvim.homeManagerModules.default
  ];
}
