{ lib, config, pkgs, ... }:

let
  inherit (lib) mkDefault mkIf strings;

  # Helper function to read environment variables with fallback
  envOr = envVar: fallback:
    let envValue = builtins.getEnv envVar;
    in if envValue != "" then envValue else fallback;

  # Helper function to read boolean environment variables
  envBoolOr = envVar: fallback:
    let envValue = builtins.getEnv envVar;
    in if envValue != "" then
      (envValue == "true" || envValue == "1" || envValue == "yes")
    else fallback;
in
{
  imports = [ ./options.nix ];

  # Default configuration values – fields can be overridden by environment variables.
  config.jacks-nix = {
    configRepoPath = mkDefault (envOr "JACKS_NIX_CONFIG_REPO_PATH" "$HOME/.config/jacks-nix");

    user = {
      name     = mkDefault (envOr "JACKS_NIX_USER_NAME" "Jack Coy");
      email    = mkDefault (envOr "JACKS_NIX_USER_EMAIL" "jackman3000@gmail.com");
      username = mkDefault (envOr "JACKS_NIX_USER_USERNAME" "jack");
    };

    mac = {
      nixbldUserId     = mkDefault (strings.toInt (envOr "JACKS_NIX_MAC_NIXBLD_USER_ID" "300"));
      nixbldGroupId    = mkDefault (strings.toInt (envOr "JACKS_NIX_MAC_NIXBLD_GROUP_ID" "350"));
    };

    enableGit      = mkDefault (envBoolOr "JACKS_NIX_ENABLE_GIT" true);
    enableZsh      = mkDefault (envBoolOr "JACKS_NIX_ENABLE_ZSH" true);
    zshTheme       = mkDefault (envOr "JACKS_NIX_ZSH_THEME" "ys");
    enableNvim     = mkDefault (envBoolOr "JACKS_NIX_ENABLE_NVIM" true);
    enableHomebrew = mkDefault (envBoolOr "JACKS_NIX_ENABLE_HOMEBREW" pkgs.stdenv.isDarwin);

    enablePython = mkDefault (envBoolOr "JACKS_NIX_ENABLE_PYTHON" false);
    enableNode   = mkDefault (envBoolOr "JACKS_NIX_ENABLE_NODE" false);
    enableJava   = mkDefault (envBoolOr "JACKS_NIX_ENABLE_JAVA" false);
    enableRuby   = mkDefault (envBoolOr "JACKS_NIX_ENABLE_RUBY" false);
    enableBun    = mkDefault (envBoolOr "JACKS_NIX_ENABLE_BUN" false);
    enableAsdf   = mkDefault (envBoolOr "JACKS_NIX_ENABLE_ASDF" false);
  };
}
