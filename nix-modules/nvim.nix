{ config, pkgs, lib, ... }:
{
  config = lib.mkIf config.jacks-nix.enableNvim {
    # These packages are dependencies for nvim plugins and will only be installed
    # when nvim is enabled.
    home.packages = with pkgs; [
      neovim
      ripgrep
      fd
      nodejs_20
      tree-sitter
      lua-language-server
      stylua
      shellcheck
      shfmt

      # Mason dependencies
      unzip
      rustup
      go
      ruby
      python3
      python3Packages.pip
      python3Packages.setuptools
      python3Packages.wheel
      python3Packages.virtualenv
      python3Packages.flake8

      # C compiler and build tools
      clang
      cmake
      gnumake
      pkg-config
    ];

    home.sessionVariables = {
      EDITOR = "nvim";
    };


    # Symlink your existing LazyVim config from the assets directory
    home.file.".config/nvim".source = ../assets/nvim;
  };
}
