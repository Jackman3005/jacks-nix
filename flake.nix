{
  description = "Jack's Nix Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixvim, nix-darwin, ... }@inputs:
  let
    lib = nixpkgs.lib;
    specialArgs = { inherit inputs; };

    localMachineOverrides = self + "/local/machine.local.nix";

    sharedModules = [
      ./config
    ]
    ++ (lib.optional (builtins.pathExists localMachineOverrides) localMachineOverrides);
  in
  {
    # Home Manager Configurations (for non-NixOS Linux)
    homeConfigurations = {
      "linux-x64" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { system = "x86_64-linux"; };
        extraSpecialArgs = specialArgs;
        modules = sharedModules ++ [ ./hosts/linux-x64 ];
      };
    };

    # Darwin Configurations (for macOS)
    darwinConfigurations = {
      "mac-arm64" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = specialArgs;
        modules = sharedModules ++ [ ./hosts/mac-arm64 ];
      };
    };
  };
}
