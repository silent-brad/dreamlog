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
        pkgs = import nixpkgs { inherit system; };
        ocamlPkgs = pkgs.ocamlPackages;

        orgcamlLib = ocamlPkgs.buildDunePackage {
          pname = "orgcaml";
          version = "0.1.0";
          src = orgcaml;
          duneVersion = "3";
          propagatedBuildInputs = [ ocamlPkgs.angstrom ];
        };

        mirage-nix = hillingar.lib.${system};
        inherit (mirage-nix) mkUnikernelPackages;

        mkDreamlog =
          {
            src,
            config ? "config.lua",
            port ? 8080,
          }:
          let
            generator = pkgs.stdenv.mkDerivation {
              name = "dreamlog-generator";
              src = self + "/generator";
              nativeBuildInputs = with ocamlPkgs; [
                ocaml
                dune_3
                findlib
              ];
              buildInputs = [
                ocamlPkgs.jingoo
                ocamlPkgs.ocaml-lua
                orgcamlLib
                pkgs.lua5_1
              ];
              buildPhase = "dune build";
              installPhase = ''
                mkdir -p $out/bin
                cp _build/default/main.exe $out/bin/dreamlog-gen
              '';
            };

            site = pkgs.runCommand "dreamlog-site" { } ''
              mkdir -p $out
              cd ${src}
              ${generator}/bin/dreamlog-gen ${config} $out
            '';

            unikernelSrc = pkgs.runCommand "dreamlog-src" { } ''
              mkdir -p $out/mirage
              cp ${self}/mirage/config.ml $out/mirage/config.ml
              sed 's/`TCP 8080/`TCP ${toString port}/' ${self}/mirage/unikernel.ml > $out/mirage/unikernel.ml
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
