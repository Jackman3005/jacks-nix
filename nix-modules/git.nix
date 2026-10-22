{ config, pkgs, lib, ... }:
let
  signingEnabled = config.jacks-nix.git.signingKey != "";

  # Refuse to build with a malformed or placeholder commit email. A test value
  # (test$special@example.com) once leaked into local/config.env and every
  # commit for months used it. Reserved domains per RFC 2606 / RFC 6761.
  email = config.jacks-nix.git.email;
  emailMatch = builtins.match "[^@[:space:]]+@([^@[:space:]]+\\.[^@[:space:]]+)" email;
  emailDomain = if emailMatch == null then "" else lib.toLower (builtins.head emailMatch);
  emailTld = lib.last (lib.splitString "." emailDomain);
  emailIsPlaceholder =
    builtins.elem emailDomain [ "example.com" "example.org" "example.net" ]
    || builtins.elem emailTld [ "test" "example" "invalid" "localhost" ];
in
{

  config = lib.mkIf config.jacks-nix.enableGit {
    assertions = [
      {
        assertion = emailMatch != null && !emailIsPlaceholder;
        message = ''
          jacks-nix: refusing to configure Git with commit email "${email}" —
          it is ${if emailMatch == null then "not a valid email address" else "a reserved test/placeholder domain (${emailDomain})"}.
          Fix it with `jacks-nix reconfigure`, or check for a stray JACKS_NIX_GIT_EMAIL
          in your environment or local/config.env.
        '';
      }
    ];

    programs.git = {
      enable = true;
      package = if pkgs.stdenv.hostPlatform.isLinux then pkgs.gitMinimal else pkgs.git;
      settings = lib.mkMerge [
            {
              user = {
                name = config.jacks-nix.git.name;
                email = config.jacks-nix.git.email;
              };
              init.defaultBranch = "main";
              rebase.autoStash   = true;
              core.editor        = "vi";
              alias = {
                bl = ''!list_recent_branches() { local lines=$1; git branch --sort=committerdate --format="%(align:width=20)%(committerdate:relative)%(end)%(align:width=20)%(committername)%(end)%(if)%(refname:rstrip=3)%(then)%(color:dim)%(else)%(end)%(align:width=50)%(HEAD)%(refname:short)%(color:reset)%(if)%(upstream:track)%(then)%(color:bold yellow) %(upstream:track)%(else)%(end)%(end)%(color:reset)" --color --all | tail -"''${lines:-25}"; }; list_recent_branches'';
                c = "commit";
                ca = "commit --amend --no-edit";
                cp = "cherry-pick";
                l = ''log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative'';
                ld = ''!get_default_branch() { git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main"; }; git --no-pager log origin/''${1:-$(get_default_branch)}..HEAD --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative'';
                changes = ''!f() { \
            get_default_branch() { git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main"; }; \
            url=$(git config --get remote.origin.url); \
            if echo "$url" | grep -q "git@"; then \
                base_url=$(echo "$url" | sed -e 's/\.git$//' -e 's/git@//' -e 's#:#/#' -e 's#^#https://#'); \
            else \
                base_url=$(echo "$url" | sed 's/\.git$//'); \
            fi; \
            if echo "$base_url" | grep -q "github.com"; then \
                commit_path_segment="commit"; \
            elif echo "$base_url" | grep -q "gitlab.com"; then \
                commit_path_segment="-/commit"; \
            elif echo "$base_url" | grep -q "bitbucket.org"; then \
                commit_path_segment="commits"; \
            else \
                commit_path_segment="commit"; \
            fi; \
            commit_url_prefix="$base_url/$commit_path_segment"; \
            git --no-pager log --no-merges origin/''${1:-$(get_default_branch)}..HEAD --pretty="format:[%s]($commit_url_prefix/%H)%n%b"; \
        }; f'';
                co = "checkout";
                s = "status";
                st = "status";
                a = "add";
                pr = "pull --rebase";
                pu = ''!push() { if git rev-parse --abbrev-ref --symbolic-full-name @{u} > /dev/null 2>&1; then git push $@; else git push --set-upstream origin $(git symbolic-ref --short HEAD) $@; fi; }; push'';
                ri = ''!get_default_branch() { git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main"; }; git rebase --interactive origin/$(get_default_branch)'';
              };
            }
            (lib.mkIf signingEnabled {
              user.signingkey = "key::${config.jacks-nix.git.signingKey}";
              gpg.format      = "ssh";
              commit.gpgsign  = true;
            })
            (lib.mkIf (signingEnabled && pkgs.stdenv.hostPlatform.isDarwin) {
              gpg."ssh".program =
                "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
            })
            (lib.mkIf (signingEnabled && !pkgs.stdenv.hostPlatform.isDarwin) {
              gpg."ssh".program = "ssh-keygen";
            })
          ];
    };
  };
}
