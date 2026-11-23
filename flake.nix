{
  description = "jailoc with its VM runtime, packaged for Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    # Linux only for now; aarch64-darwin needs a Darwin VM runtime (see README Roadmap).
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    packages = forAllSystems (system: let
      packages = import ./pkgs nixpkgs.legacyPackages.${system};
    in
      packages // {default = packages.jailoc;});

    # Re-exports our build so consumers keep the nixpkgs revision it was tested with.
    overlays.default = final: _prev: {
      jailoc = self.packages.${final.stdenv.hostPlatform.system}.jailoc;
    };

    checks = forAllSystems (system: {
      inherit (self.packages.${system}) jailoc;
    });

    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          nix-update
          alejandra
          git
        ];
      };
    });

    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
  };
}
