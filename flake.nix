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
    specialArgs = { inherit inputs; };
  in
  {
    # Home Manager Configurations (for non-NixOS Linux)
    homeConfigurations = {
      "linux-x64" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { system = "x86_64-linux"; };
        extraSpecialArgs = specialArgs;
        modules = [
          ./config
          ./hosts/linux-x64
         ];
      };
    };

    # Darwin Configurations (for macOS)
    darwinConfigurations = {
      "mac-arm64" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = specialArgs;
        modules = [
            ./config
            ./hosts/mac-arm64
         ];
      };
    };
  };
}
