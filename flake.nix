{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    hillingar.url = "github:ryanGibb/hillingar";
    orgcaml.url = "github:silent-brad/orgcaml";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      hillingar,
      orgcaml,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ orgcaml.overlays.default ];
        };
        ocamlPkgs = pkgs.ocamlPackages;

        mirage-nix = hillingar.lib.${system};
        inherit (mirage-nix) mkUnikernelPackages;

        mkDreamlog =
          {
            src,
          }:
          let
            siteSrc = src;

            site = pkgs.stdenv.mkDerivation {
              name = "dreamlog-site";
              src = self + "/generator";
              nativeBuildInputs = with ocamlPkgs; [
                ocaml
                dune_3
                findlib
              ];
              buildInputs = [
                ocamlPkgs.jingoo
                ocamlPkgs.ocaml-lua
                ocamlPkgs.orgcaml
                pkgs.lua5_1
              ];
              buildPhase = "dune build";
              installPhase = ''
                mkdir -p $out
                _build/default/main.exe ${siteSrc}/site.lua $out
              '';
            };

            unikernelSrc = pkgs.runCommand "dreamlog-src" { } ''
              mkdir -p $out/mirage
              cp ${self}/mirage/config.ml $out/mirage/config.ml
              cp ${self}/mirage/unikernel.ml $out/mirage/unikernel.ml
              cp -r ${site} $out/htdocs
            '';
          in
          mkUnikernelPackages {
            unikernelName = "dreamlog";
            mirageDir = "mirage";
            depexts = with pkgs; [
              solo5
              gmp
            ];
            monorepoQuery = {
              ocaml-base-compiler = "*";
              jsonm = "1.0.1+dune";
              uutf = "1.0.3+dune";
            };
            query = {
              mirage = "4.5.0";
              ocaml-base-compiler = "*";
            };
          } unikernelSrc;
      in
      {
        lib.mkDreamlog = mkDreamlog;
      }
    );
}
