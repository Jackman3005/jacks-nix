{ lib, ... }:
{
  imports = [ ./options.nix ];

  jacks-nix = {
    # Set your personal details here
    user = {
      name = "Jack Coy";
      email = "jackman3000@gmail.com";
      username = "jack";
    };

    # Toggle features on or off
    enableGit = lib.mkDefault true;
    enableZsh = lib.mkDefault true;
    enableNvim = lib.mkDefault true;
    enableHomebrew = lib.mkDefault true;

    # Disable programming language tools by default on Linux
    enablePython = lib.mkDefault false;
    enableNode = lib.mkDefault false;
    enableJava = lib.mkDefault false;
    enableRuby = lib.mkDefault false;
    enableBun = lib.mkDefault false;
    enableAsdf = lib.mkDefault false;
  };
}
