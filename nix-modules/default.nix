{
  imports = [
    # Import your personal settings so all modules can see them
    ../config

    # Import all the feature modules
    ./git.nix
    ./shell.nix
    ./nvim.nix
    ./homebrew.nix
  ];
}
