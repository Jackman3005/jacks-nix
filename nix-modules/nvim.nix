{ config, pkgs, lib, ... }:
{
  config = lib.mkIf config.jacks-nix.enableNvim {
    # These packages are dependencies for nvim plugins and will only be installed
    # when nvim is enabled.
    home.packages = with pkgs; [
      neovim
      ripgrep
      fd
      nodejs_24
      tree-sitter
      unzip

      # Pre-built LSPs
      lua-language-server
      typescript-language-server
      vscode-langservers-extracted
      bash-language-server
      yaml-language-server
      md-lsp
      nil

      # Formatters/Linters
      stylua
      shellcheck
      shfmt
      nodePackages.prettier

      # Python (for pynvim)
      python3
      python3Packages.pynvim
    ];

    home.sessionVariables = {
      EDITOR = "nvim";
    };


    # Symlink your existing LazyVim config from the assets directory
    home.file.".config/nvim".source = ../assets/nvim;
  };
}
