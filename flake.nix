{
  description = "Jack's Nix Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixvim, nix-darwin, ... }@inputs:
  let
    specialArgs = { inherit inputs; };
    # Get username from your central config to avoid hardcoding
    username = self.lib.jacks-nix.user.username;
  in
  {
    # Expose your custom options and default values as a reusable library
    lib = import ./config;

    # Home Manager Configurations (for non-NixOS Linux)
    homeConfigurations = {
      "ubuntu-x64" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        extraSpecialArgs = specialArgs;
        modules = [ ./hosts/ubuntu-x64/home.nix ];
      };
    };

    # Darwin Configurations (for macOS)
    darwinConfigurations = {
      "mac-arm64" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = specialArgs;
        modules = [
          # 1. Import the home-manager module for darwin
          inputs.home-manager.darwinModules.home-manager

          # 2. Define the system user and link to the home.nix config
          ({ config, pkgs, ... }: {
            # Pass specialArgs down to home-manager
            home-manager.extraSpecialArgs = specialArgs;

            # Backup existing files that would be overwritten
            home-manager.backupFileExtension = "backup";

            # Set the state version
            system.stateVersion = 4;

            # Fix GID mismatch for nixbld group
            ids.gids.nixbld = 350;

            # Create the user account
            users.users.${username} = {
              name = username;
              home = "/Users/${username}";
            };

            # Import nixvim module for home-manager
            home-manager.sharedModules = [
              inputs.nixvim.homeManagerModules.default
            ];

            # Assign the home-manager configuration for that user
            home-manager.users.${username} = import ./hosts/mac-arm64/home.nix;
          })
        ];
      };
    };
  };
}
