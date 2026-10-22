{ config, pkgs, lib, ... }:
{
  config = lib.mkIf config.jacks-nix.enableZsh {

    home.packages = with pkgs; [
      bat
      tree
      eza
      jq
      zellij
      curl
      wget
      uv
      fd
    ];

    programs.home-manager.enable = true;

    home.shell.enableZshIntegration = true;
    home.shellAliases = {
      "..." = "cd ../..";
      "...." = "cd ../../..";
      "....." = "cd ../../../..";
      "......" = "cd ../../../../..";
      "......." = "cd ../../../../../..";
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

    programs.starship = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        add_newline = false;

        format = lib.concatStrings [
          "[#](bold blue) "
          "$username"
          "$hostname"
          "[ in ](white)"
          "$directory"
          "$git_branch"
          "$git_status"
          "$python"
          "[ \\[](white)$time[\\]](white)"
          "$status"
          "\n"
          "$character"
        ];

        username = {
          style_user = "cyan";
          style_root = "black bg:yellow";
          format = "[$user]($style)";
          show_always = true;
        };

        hostname = {
          ssh_only = true;
          format = "[@](white)[$hostname]($style)";
          style = "green";
        };

        directory = {
          style = "yellow bold";
          format = "[$path]($style)";
          truncation_length = 3;
          truncation_symbol = ".../";
        };

        git_branch = {
          symbol = "";
          style = "purple";
          format = "[ on ](white)[$branch]($style)";
        };

        git_status = {
          format = "([$all_status$ahead_behind]($style))";
          style = "yellow";
          conflicted = "[!](bold red)";
          stashed = "";
          untracked = "?";
          modified = "*";
          staged = "+";
          ahead = "[⇡\${count}](cyan)";
          behind = "[⇣\${count}](magenta)";
          diverged = "[⇕⇡\${ahead_count}⇣\${behind_count}](magenta)";
        };

        kubernetes = {
          disabled = true;
        };

        python = {
          symbol = "";
          style = "green";
          format = "[ (venv:$virtualenv)]($style)";
          detect_extensions = [];
          detect_files = [];
          detect_folders = [];
        };

        time = {
          disabled = false;
          format = "[$time]($style)";
          style = "white";
          time_format = "%T";
        };

        status = {
          disabled = false;
          format = "[ C:$status]($style)";
          style = "red";
        };

        cmd_duration = {
          min_time = 2000;
          format = "[$duration]($style) ";
          style = "yellow";
        };

        character = {
          success_symbol = "[\\$](bold green)";
          error_symbol = "[\\$](bold red)";
        };

        nodejs.disabled = true;
        rust.disabled = true;
        golang.disabled = true;
        package.disabled = true;
        docker_context.disabled = true;
        aws.disabled = true;
        gcloud.disabled = true;
      };
    };

    programs.fzf = {
      enable = true;
      enableZshIntegration = true;
      defaultCommand = "fd --type f --hidden --follow --exclude .git";
      fileWidgetCommand = "fd --type f --hidden --follow --exclude .git";
      defaultOptions = [ "--height 40%" "--layout=reverse" "--border" ];
    };

    programs.direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    programs.zsh = {
      enable = true;
      autocd = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      enableCompletion = true;
      # Explicit, rather than zsh inferring vi mode from EDITOR=vi
      defaultKeymap = "viins";

      history = {
        size = 100000;
        append = true;
        extended = true;
      };

      initContent = ''
        export EDITOR=vi

        # Vi mode, keeping the familiar emacs/macOS keys working in insert mode.
        # 200ms to assemble an escape sequence (Esc b, Esc [3~) — local is instant,
        # but SSH can split a sequence across packets. Default 400ms makes Esc feel laggy.
        KEYTIMEOUT=20
        # Without these, unbound keys either type a literal ^X or start with Esc,
        # which drops you into command mode.
        bindkey -M viins '^A' beginning-of-line '^E' end-of-line   # also Ghostty Cmd+←/→
        bindkey -M viins '^U' backward-kill-line                   # also Ghostty Cmd+Backspace
        bindkey -M viins '^K' kill-line
        bindkey -M viins '^W' backward-kill-word
        bindkey -M viins '^Y' yank
        # Literal newline: Ghostty Shift+Enter sends \n (^J); Enter is ^M and still submits
        bindkey -M viins '^J' self-insert-unmeta '^[^M' self-insert-unmeta  # also Alt+Enter
        bindkey -M viins '^?' backward-delete-char '^H' backward-delete-char  # past the insert point
        bindkey -M viins '^[b' backward-word '^[f' forward-word    # also Ghostty Option+←/→
        bindkey -M viins '^[d' kill-word '^[^?' backward-kill-word
        for keymap in viins vicmd; do
          bindkey -M $keymap '^[[H' beginning-of-line '^[OH' beginning-of-line  # Home
          bindkey -M $keymap '^[[F' end-of-line       '^[OF' end-of-line        # End
          bindkey -M $keymap '^[[1;3D' backward-word  '^[[1;3C' forward-word   # Option+←/→ (CSI form)
          bindkey -M $keymap '^[[1;5D' backward-word  '^[[1;5C' forward-word   # Ctrl+←/→
        done
        bindkey -M viins '^[[3~' delete-char                        # Delete
        bindkey -M vicmd '^[[3~' vi-delete-char
        # vv in command mode opens the line in $EDITOR
        autoload -U edit-command-line && zle -N edit-command-line
        bindkey -M vicmd 'vv' edit-command-line

        # Tool completions
        command -v kubectl &>/dev/null && source <(kubectl completion zsh)
        command -v docker &>/dev/null && source <(docker completion zsh)

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
