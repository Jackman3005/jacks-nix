{ pkgs, config, inputs, ... }:
{
  imports = [
    # Import home-manager module for NixOS
    inputs.home-manager.nixosModules.home-manager
  ];

  # Your NixOS system configuration
  system.stateVersion = "23.11";

  # Enable declarative nix.conf
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Basic system configuration
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda"; # Replace with your actual boot device
  };

  # Basic file system configuration (replace with your actual setup)
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # User configuration
  users.users.jack = {
    isNormalUser = true;
    group = "jack";
    extraGroups = [ "wheel" "networkmanager" ];
  };

  users.groups.jack = {};

  # Enable sudo for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Home Manager configuration
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.jack = import ./home.nix;

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
