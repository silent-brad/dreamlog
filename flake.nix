{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    hillingar.url = "github:ryanGibb/hillingar";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      hillingar,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages =
          let
            mirage-nix = (hillingar.lib.${system});
            inherit (mirage-nix) mkUnikernelPackages;
          in
          mkUnikernelPackages {
            unikernelName = "mirage-site";
            # list external dependancies here
            depexts = with pkgs; [
              solo5
              gmp
            ];
            # solve for non-trunk compiler
            monorepoQuery = {
              ocaml-base-compiler = "*";
              # https://github.com/RyanGibb/hillingar/issues/3
              jsonm = "1.0.1+dune";
              uutf = "1.0.3+dune";
            };
            query = {
              mirage = "4.5.0";
              ocaml-base-compiler = "*";
            };
          } ./.;

        defaultPackage = self.packages.${system}.unix;
      }
    );
}
