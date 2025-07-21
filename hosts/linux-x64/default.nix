{ pkgs, config, inputs, ... }:
let
  username = config.jacks-nix.user.username;
in
{
  imports = [
    inputs.home-manager.homeManagerModules.home-manager
  ];

  # Enable declarative nix.conf
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Home Manager configuration
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.${username} = import ./home.nix;

  # Pass nixvim to home-manager modules
  home-manager.extraSpecialArgs = {
    inherit (inputs) nixvim;
    system = "x86_64-linux";
  };

  # Import nixvim module for home-manager
  home-manager.sharedModules = [
    inputs.nixvim.homeManagerModules.default
  ];
}
