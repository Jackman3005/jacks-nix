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
      direnv
      zsh-autosuggestions
      zsh-syntax-highlighting
      curl
      wget
      git
    ];

    programs.home-manager.enable = true;

    home.shell.enableZshIntegration = true;
    home.shellAliases = {
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
      scripts = ''cat package.json | jq ".scripts"'';
      sshpw = "ssh -o PubkeyAuthentication=no";
      myip =
        if pkgs.stdenv.isDarwin then "ipconfig getifaddr $(route get default | grep interface | cut -d' ' -f4)"
        else "ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i==\"src\") print $(i+1)}'";
    };

    programs.zsh = {
      enable = true;

      oh-my-zsh = {
        enable = true;
        theme = config.jacks-nix.zshTheme;
        plugins = [
          "git"
          "docker"
          "kubectl"
          "direnv"
          "fzf"
        ] ++ lib.optionals (config.jacks-nix.enableHomebrew && pkgs.stdenv.isDarwin) [ "brew" ];
      };

      history = {
        size = 100000;
        append = true;
        extended = true;
      };

      initContent = ''
        # Skip user-blocking script when parent process does not have the ability to respond.
        if [ -z "$INTELLIJ_ENVIRONMENT_READER" ]; then
            # Check for updates and prompt user if present. Limited to once per 24 hours.
            jacks-nix-update-check
        fi


        export EDITOR=vi

        export FZF_BASE_DIR="${pkgs.fzf}/share/fzf"
        export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_PREVIEW_COMMAND='bat --style=numbers --color=always --line-range :500 {}'
        export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

        ${lib.optionalString config.jacks-nix.enablePython ''
          # Setup pyenv configuration
          export PYENV_ROOT="$HOME/.pyenv"
          [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
          if command -v pyenv >/dev/null 2>&1; then
            eval "$(pyenv init - zsh)"
          fi
        ''}

        ${lib.optionalString config.jacks-nix.enableNode ''
          # NVM manages installed node versions
          export NVM_DIR="$HOME/.nvm"
          [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
          [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
        ''}

        ${lib.optionalString config.jacks-nix.enableBun ''
          # bun completions
          [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

          # bun
          export BUN_INSTALL="$HOME/.bun"
          export PATH="$BUN_INSTALL/bin:$PATH"
        ''}

        ${lib.optionalString config.jacks-nix.enableJava ''
          # SDKMAN manages installed java versions
          export SDKMAN_DIR="$HOME/.sdkman"
          [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
          export SDKMAN_OFFLINE_MODE=false
        ''}

        ${lib.optionalString config.jacks-nix.enableRuby ''
          # Ruby configuration
          if command -v ruby >/dev/null 2>&1; then
            # Add Ruby gems bin to PATH
            export PATH="$(ruby -e 'puts Gem.user_dir')/bin:$PATH"
          fi
        ''}

        ${lib.optionalString config.jacks-nix.enableAsdf ''
          # ASDF version manager
          if [ -f "$HOME/.asdf/asdf.sh" ]; then
            source "$HOME/.asdf/asdf.sh"

            # append completions to fpath
            fpath=(''${ASDF_DIR}/completions $fpath)
            # initialise completions with ZSH's compinit
            autoload -Uz compinit && compinit
          fi
        ''}

        # Source ~/.aliases if it exists
        if [[ -f "$HOME/.aliases" ]]; then
          source "$HOME/.aliases"
        fi

        # Source ~/.zshrc.local if it exists
        if [[ -f "$HOME/.zshrc.local" ]]; then
          source "$HOME/.zshrc.local"
        fi
      '';
    };
  };
}
