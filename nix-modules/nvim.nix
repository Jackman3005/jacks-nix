{ config, pkgs, lib, ... }:
{
  config = lib.mkIf config.jacks-nix.enableNvim {
    programs.nixvim = {
      enable = true;
      package = pkgs.neovim-unwrapped;
    };

    # These packages are dependencies for nvim plugins and will only be installed
    # when nvim is enabled.
    home.packages = with pkgs; [
      ripgrep
      fd
      nodejs_20
      tree-sitter
      lua-language-server
      stylua
      shellcheck
      shfmt
      python3Packages.flake8

      # Mason dependencies
      unzip
      cargo
      rustc
      go
      ruby
    ];

    home.sessionVariables = {
      EDITOR = "nvim";
    };


    # Symlink your existing LazyVim config from the assets directory
    home.file.".config/nvim".source = ../assets/nvim;
  };
}
