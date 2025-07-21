{ lib, config, pkgs, ... }:

let
  inherit (lib) mkDefault;
in
{
  imports = [ ./options.nix ];

  # actual defaults – every field can still be overridden later
  config.jacks-nix = {
    configRepoPath = mkDefault "~/.config/jacks-nix";

    user = {
      name     = mkDefault "Jack Coy";
      email    = mkDefault "jackman3000@gmail.com";
      username = mkDefault "jack";
    };

    enableGit      = mkDefault true;
    enableZsh      = mkDefault true;
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
