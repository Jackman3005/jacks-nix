{ lib, config, pkgs, inputs, ... }:

let
  inherit (lib) mkDefault;
  # Use the path to the local-machine config from the flake input
  localConfig = "${inputs.self-local}/machine.local.nix";
in
{
  imports = [ ./options.nix ]
    # Conditionally import machine-local overrides if the file exists.
    ++ (lib.optional (builtins.pathExists localConfig) localConfig);

  # actual defaults – every field can still be overridden later
  config.jacks-nix = {
    configRepoPath = mkDefault "$HOME/.config/jacks-nix";

    user = {
      name     = mkDefault "Jack Coy";
      email    = mkDefault "jackman3000@gmail.com";
      username = mkDefault "jack";
    };

    enableGit      = mkDefault true;
    enableZsh      = mkDefault true;
    zshTheme       = mkDefault "ys";
    enableNvim     = mkDefault true;
    enableHomebrew = mkDefault pkgs.stdenv.isDarwin;

    enablePython = mkDefault false;
    enableNode   = mkDefault false;
    enableJava   = mkDefault false;
    enableRuby   = mkDefault false;
    enableBun    = mkDefault false;
    enableAsdf   = mkDefault false;
  };
}
