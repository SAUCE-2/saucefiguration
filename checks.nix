# `nix flake check`. Built per system, for the profiles of that system.
{
  pkgs,
  self,
  homes,
}:
let
  inherit (pkgs) lib;

  # Starts the profile's real ~/.zshrc in an interactive zsh, from a copy of
  # its home-files and with its packages on PATH. Fails on a syntax error, on
  # any startup output other than the test's own, or if the widget plugins
  # load out of order. zsh runs on a pseudo-terminal (zsh/zpty): without one,
  # zle is off and the fzf scripts complain.
  zshrcCheck =
    name: home:
    pkgs.runCommand "zshrc-${name}"
      {
        nativeBuildInputs = [
          pkgs.gnugrep
          # Stands in for the system's OpenSSH, which the ssh-agent plugin starts.
          pkgs.openssh
        ];
      }
      ''
        export HOME=$TMPDIR/home
        export PATH=${home.config.home.path}/bin:$PATH
        mkdir -p "$HOME"
        cp -rL ${home.config.home-files}/. "$HOME"
        chmod -R u+w "$HOME"
        rc=$HOME/.zshrc

        zsh -n "$rc"

        # Line of the first match of $1 in .zshrc.
        line() {
          grep -n -F -- "$1" "$rc" | head -n 1 | cut -d: -f1
        }
        prev=0
        for marker in oh-my-zsh.sh fzf-tab.plugin.zsh zsh-autosuggestions.zsh zsh-syntax-highlighting.zsh; do
          n=$(line "$marker")
          if [ -z "$n" ] || [ "$n" -le "$prev" ]; then
            echo "$marker is missing or loads too early in .zshrc" >&2
            exit 1
          fi
          prev=$n
        done

        got=$(zsh -f -c '
          zmodload zsh/zpty
          zpty z "TERM=dumb zsh -i -c \"echo started\" 2>&1"
          while zpty -r z line; do print -rn -- "''${line//$'"'\r'"'/}"; done
          zpty -d z
        ')
        if [ "$got" != started ]; then
          printf 'zsh startup printed more than "started":\n%s\n' "$got" >&2
          exit 1
        fi
        touch $out
      '';
in
lib.mapAttrs' (name: home: lib.nameValuePair "home-${name}" home.activationPackage) homes
// lib.mapAttrs' (name: home: lib.nameValuePair "zshrc-${name}" (zshrcCheck name home)) homes
// {
  nixfmt = pkgs.runCommand "nixfmt" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
    cd ${self}
    find . -name '*.nix' -exec nixfmt --check {} +
    touch $out
  '';

  shellcheck = pkgs.runCommand "shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
    cd ${self}
    shellcheck zsh/*.sh ssh/*.sh .github/*.sh
    touch $out
  '';
}
