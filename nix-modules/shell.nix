{ config, pkgs, lib, ... }:
{
  config = lib.mkIf config.jacks-nix.enableZsh {
    home.packages = with pkgs; [
      bat
      tree
      fzf
      eza
      jq
      zellij
    ];

    programs.home-manager.enable = true;

    programs.zsh = {
      enable = true;
      oh-my-zsh = {
        enable = true;
        theme = "ys";
      };
      shellAliases = {
        g = "git";
        vi = "nvim";
        cat = "bat";
        ll = "eza --long --octal-permissions --header --no-permissions --no-user --all --time-style '+%y-%b-%d %l:%M%P' --color-scale=age --group-directories-first --hyperlink";
        d = "docker";
        dc = "docker-compose";
        dcr = "docker-compose down && docker-compose up -d";
        dcu = "docker-compose down && docker-compose pull && docker-compose up -d";
        k = "kubectl";
        z = "zellij";
        scripts=''cat package.json | jq ".scripts"'';
        sshpw="ssh -o PubkeyAuthentication=no";
        myip =
          if pkgs.stdenv.isDarwin then "ipconfig getifaddr $(route get default | grep interface | cut -d' ' -f4)"
          else "ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i==\"src\") print $(i+1)}'";
        update =
          if pkgs.stdenv.isDarwin then "sudo darwin-rebuild switch --flake ~/.config/nix-config#mac-arm64 && exec zsh"
          else "home-manager switch --flake ~/.config/nix-config#ubuntu-x64 && exec zsh";
      };
      history.size = 100000;
      initContent = ''
        export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_PREVIEW_COMMAND='bat --style=numbers --color=always --line-range :500 {}'
      '';
    };

    programs.fzf = {
      enable = true;
    };
  };
}
