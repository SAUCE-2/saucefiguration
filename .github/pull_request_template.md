<!-- Title: conventional commit scoped by directory, e.g. `feat(zsh): ...`.
     It becomes the squash commit on main. -->

## What and why



## Checked

- [ ] CI is green (`nix flake check`, script tests and a real install, on Linux and macOS)
- [ ] New tools come from Nix (`home.packages` in `home.nix` or a `programs.*` module)
- [ ] macOS-only or WSL-only behaviour is conditional, not a separate copy
