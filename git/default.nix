# git, written to ~/.config/git/config (and the ignore list to
# ~/.config/git/ignore). A leftover ~/.gitconfig would win over it, so
# zsh/install.sh moves the one the old installer copied out of the way.
{ ... }:
{
  programs.git = {
    enable = true;

    # Commits and tags are SSH-signed with the key ssh-agent holds.
    signing = {
      format = "ssh";
      key = "~/.ssh/id_ed25519.pub";
      signByDefault = true;
    };

    ignores = [ ".DS_Store" ];

    settings = {
      user = {
        name = "s";
        email = "s@sauce2.com";
      };

      core = {
        autocrlf = "input";
        untrackedCache = true;
        longpaths = true;
      };

      init.defaultBranch = "main";

      diff = {
        algorithm = "histogram";
        colorMoved = "default";
      };

      branch.sort = "-committerdate";

      help.autocorrect = "prompt";

      merge = {
        ff = true;
        conflictstyle = "zdiff3";
      };

      rerere.enabled = true;

      rebase.autoStash = true;

      push = {
        autoSetupRemote = true;
        followTags = true;
      };

      pull = {
        rebase = true;
        ff = true;
      };

      # No pruneTags: it deletes unpushed local tags on every fetch.
      fetch.prune = true;

      # ssh/default.nix links this file into place.
      gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";

      feature.manyFiles = true;

      pack.threads = 0;
    };
  };

  # Syntax-highlighted diffs: git's pager and interactive diff filter.
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
    };
  };
}
