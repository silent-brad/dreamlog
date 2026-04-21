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
        ocamlPkgs = pkgs.ocamlPackages;

        orgcaml = ocamlPkgs.buildDunePackage {
          pname = "orgcaml";
          version = "unstable";
          src = pkgs.fetchFromGitHub {
            owner = "silent-brad";
            repo = "orgcaml";
            rev = "50f0b13cd8733d76566ac9d3b8214681e3d8661f";
            sha256 = "sha256-wTZS9ifwa3BJsZC/dlmrGWdYKCLFdhOKlseFip1XJ6Y=";
          };
          propagatedBuildInputs = [
            ocamlPkgs.angstrom
          ];
        };

        generator = pkgs.stdenv.mkDerivation {
          name = "site-generator";
          src = ./generator;
          nativeBuildInputs = [
            ocamlPkgs.ocaml
            ocamlPkgs.dune_3
            ocamlPkgs.findlib
          ];
          buildInputs = [
            ocamlPkgs.jingoo
            orgcaml
          ];
          buildPhase = "dune build";
          installPhase = ''
            mkdir -p $out/bin
            cp _build/default/main.exe $out/bin/site-generator
          '';
        };

        site = pkgs.runCommand "dreamlog-site" { nativeBuildInputs = [ generator ]; } ''
          mkdir -p $out
          site-generator ${./content} $out ${./templates} ${./static}
        '';

        # Compose source tree: inject generated site as htdocs for ocaml-crunch
        src = pkgs.runCommand "dreamlog-src" { } ''
          cp -r ${./.} $out
          chmod -R u+w $out
          rm -rf $out/generator $out/templates $out/static
          cp -r ${site} $out/htdocs
        '';

        mirage-nix = hillingar.lib.${system};
        inherit (mirage-nix) mkUnikernelPackages;
      in
      {
        packages = (
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
          } src
        );

        defaultPackage = self.packages.${system}.unix;
      }
    );
}
