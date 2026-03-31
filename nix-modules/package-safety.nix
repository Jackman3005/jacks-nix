{ config, pkgs, lib, ... }:
{
  config = {
    home.sessionVariables = lib.mkMerge [
      {
        UV_EXCLUDE_NEWER = "7 days";
      }

      (lib.mkIf config.jacks-nix.enableNode {
        npm_config_min_release_age = "7";
        pnpm_config_minimum_release_age = "10080";
        YARN_NPM_MINIMAL_AGE_GATE = "3d";
      })
    ];

    home.file = lib.mkIf config.jacks-nix.enableBun {
      ".bunfig.toml".text = ''
        [install]
        minimumReleaseAge = 604800
      '';
    };
  };
}
