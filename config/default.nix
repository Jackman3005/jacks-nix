{ lib, config, pkgs, ... }:

let
  inherit (lib) mkDefault mkIf strings;

  # Single source of truth for default values.
  defaults = builtins.fromJSON (builtins.readFile ./defaults.json);

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

  # Configuration values sourced from environment variables (set by config.env
  # via load_config in lib.sh) with fallbacks from defaults.json.
  config.jacks-nix = {
    configRepoPath = mkDefault (envOr "JACKS_NIX_CONFIG_REPO_PATH" "$HOME/.config/jacks-nix");

    # Username: env var > $USER > "jack" (runtime default is eval:whoami via schema.json)
    username = mkDefault (envOr "JACKS_NIX_USERNAME" (envOr "USER" "jack"));

    git = {
      name       = mkDefault (envOr "JACKS_NIX_GIT_NAME" defaults.gitName);
      email      = mkDefault (envOr "JACKS_NIX_GIT_EMAIL" defaults.gitEmail);
      signingKey = mkDefault (envOr "JACKS_NIX_GIT_SIGNING_KEY" defaults.gitSigningKey);
    };

    mac = {
      nixbldUserId     = mkDefault (strings.toInt (envOr "JACKS_NIX_MAC_NIXBLD_USER_ID" "350"));
      nixbldGroupId    = mkDefault (strings.toInt (envOr "JACKS_NIX_MAC_NIXBLD_GROUP_ID" "350"));
    };

    enableGit      = mkDefault (envBoolOr "JACKS_NIX_ENABLE_GIT" defaults.enableGit);
    enableZsh      = mkDefault (envBoolOr "JACKS_NIX_ENABLE_ZSH" defaults.enableZsh);
    enableNvim     = mkDefault (envBoolOr "JACKS_NIX_ENABLE_NVIM" defaults.enableNvim);
    enableHomebrew = mkDefault (envBoolOr "JACKS_NIX_ENABLE_HOMEBREW" pkgs.stdenv.isDarwin);

    enableNode   = mkDefault (envBoolOr "JACKS_NIX_ENABLE_NODE" defaults.enableNode);
    enableJava   = mkDefault (envBoolOr "JACKS_NIX_ENABLE_JAVA" defaults.enableJava);
    enableRuby   = mkDefault (envBoolOr "JACKS_NIX_ENABLE_RUBY" defaults.enableRuby);
    enableBun    = mkDefault (envBoolOr "JACKS_NIX_ENABLE_BUN" defaults.enableBun);
    enableAsdf   = mkDefault (envBoolOr "JACKS_NIX_ENABLE_ASDF" defaults.enableAsdf);
  };
}
