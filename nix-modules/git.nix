{ config, pkgs, lib, ... }:
{
  config = lib.mkIf config.jacks-nix.enableGit {
    programs.git = {
      enable = true;
      userName = config.jacks-nix.git.name;
      userEmail = config.jacks-nix.git.email;
      extraConfig = {
        init.defaultBranch = "main";
        rebase.autoStash = true;
        user.signingkey = lib.mkIf (config.jacks-nix.git.signingKey != "") config.jacks-nix.git.signingKey;
        gpg.format = lib.mkIf (config.jacks-nix.git.signingKey != "") "ssh"; 
        commit.gpgsign = lib.mkIf (config.jacks-nix.git.signingKey != "") true;
      };
      aliases = {
        bl = ''!list_recent_branches() { local lines=$1; git branch --sort=committerdate --format=\"%(align:width=20)%(committerdate:relative)%(end)%(align:width=20)%(committername)%(end)%(if)%(refname:rstrip=3)%(then)%(color:dim)%(else)%(end)%(align:width=50)%(HEAD)%(refname:short)%(color:reset)%(if)%(upstream:track)%(then)%(color:bold yellow) %(upstream:track)%(else)%(end)%(end)%(color:reset)\" --color --all | tail -\"''${lines:-25}\"; }; list_recent_branches'';
        c = "commit";
        ca = "commit --amend --no-edit";
        cp = "cherry-pick";
        l = ''log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative'';
        ld = ''!git --no-pager log origin/''${1:-development}..HEAD --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative'';
        changes = ''!f() { \
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
            git --no-pager log origin/''${1:-development}..HEAD --pretty="format:[%s]($commit_url_prefix/%H)%n%b"; \
        }; f'';
        co = "checkout";
        s = "status";
        st = "status";
        a = "add";
        pr = "pull --rebase";
        pu = ''!push() { if git rev-parse --abbrev-ref --symbolic-full-name @{u} > /dev/null 2>&1; then git push $@; else git push --set-upstream origin $(git symbolic-ref --short HEAD) $@; fi; }; push'';
        ri = "rebase --interactive origin/development";
      };
    };
  };
}
