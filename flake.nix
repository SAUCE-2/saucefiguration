{
  description = "saucefiguration: shell, git, ssh and tmux setup, managed by home-manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
    let
      lib = nixpkgs.lib;
      # Intel Macs are out: nixpkgs dropped x86_64-darwin in 26.11.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      mkHome =
        system: wsl:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [ ./home.nix ];
          extraSpecialArgs = { inherit wsl; };
        };

      # One profile per platform, so any machine can use it: zsh/install.sh
      # picks <system> or, under WSL, <system>-wsl.
      homes = lib.listToAttrs (
        lib.concatMap (
          system:
          [ (lib.nameValuePair system (mkHome system false)) ]
          ++ lib.optional (lib.hasSuffix "-linux" system) (
            lib.nameValuePair "${system}-wsl" (mkHome system true)
          )
        ) systems
      );
    in
    {
      homeConfigurations = homes;

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);

      checks = forAllSystems (
        pkgs:
        import ./checks.nix {
          inherit pkgs self;
          homes = lib.filterAttrs (
            _: home: home.activationPackage.system == pkgs.stdenv.hostPlatform.system
          ) homes;
        }
      );

      # `nix develop`: the tools the checks use, for running them by hand.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = [
            pkgs.shellcheck
            pkgs.nixfmt-tree
          ];
        };
      });
    };
}
