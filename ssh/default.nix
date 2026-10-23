# ~/.ssh: client config, allowed_signers and authorized_keys. Public keys
# only; the private key never leaves the machine it was made on.
#
# Not programs.ssh: that installs Nix's OpenSSH, and on macOS only Apple's
# ssh understands UseKeychain. The files are linked as they are instead.
{ lib, pkgs, ... }:
{
  home.file.".ssh/config".source = ./config;
  home.file.".ssh/allowed_signers".source = ./allowed_signers;

  # authorized_keys is merged into the machine's own, not linked over it
  # (see merge-authorized-keys.sh), and ~/.ssh must not be readable by others.
  home.activation.sshAuthorizedKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.ssh"
    run chmod 700 "$HOME/.ssh"
    run env PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.diffutils
        pkgs.gawk
      ]
    }" ${pkgs.bash}/bin/bash ${./merge-authorized-keys.sh} ${./authorized_keys} "$HOME/.ssh/authorized_keys"
  '';
}
