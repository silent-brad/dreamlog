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
        # OCaml package set with logseq forks overlaid
        ocamlPkgs = pkgs.ocamlPackages.overrideScope (
          final: prev: {
            angstrom = prev.buildDunePackage {
              pname = "angstrom";
              version = "dev";
              src = pkgs.fetchFromGitHub {
                owner = "logseq";
                repo = "angstrom";
                rev = "3be9b966dc2bc9ccf9948d17a7b0df1cb526de15";
                sha256 = "1sj6cmwf9xn039pcaraf2ykzldryixqlz16jcr574dgr9kjw8sng";
              };
              propagatedBuildInputs = [
                final.bigstringaf
                final.ocaml-syntax-shims
              ];
            };

            xmlm = prev.buildDunePackage {
              pname = "xmlm";
              version = "dev";
              src = pkgs.fetchFromGitHub {
                owner = "logseq";
                repo = "xmlm";
                rev = "0b085e97c75fd196649ce2e23c54f9d2502771ca";
                sha256 = "02jhi30vznl3dqwz4gzbfh6wy13dv5yq2hr16ayn77gz95n7byqh";
              };
              postPatch = ''
                cat > dune-project <<'EOF'
                (lang dune 3.0)
                (name xmlm)
                EOF
                cat > src/dune <<'EOF'
                (library
                 (name xmlm)
                 (public_name xmlm))
                EOF
                cp opam xmlm.opam
              '';
            };
          }
        );

        # mldoc CLI for org-to-HTML conversion (patched for document-mode rendering)
        mldoc = ocamlPkgs.buildDunePackage {
          pname = "mldoc";
          version = "unstable-2024-08-03";
          src = pkgs.fetchFromGitHub {
            owner = "logseq";
            repo = "mldoc";
            rev = "bedae990097fff9251cde34e685bc3cec13c01a3";
            sha256 = "07zsg35a0hc6yxkn4cpyjy6mdignhzskxi2fi8imb0r7iwl2id4z";
          };
          postPatch = ''
            # Patch heading to use level+1 when size is None (Org headings)
            # Offset by 1 so * → h2, ** → h3, etc. (h1 reserved for page title)
            substituteInPlace lib/export/html.ml \
              --replace-fail \
                '| None -> r' \
                '| None -> Xml.block (size_to_hN (level + 1)) [ r ]'

            # Patch blocks_aux to emit flat structure instead of ul/li
            sed -i '/Branch (Leaf (h, _) :: t)/,/Branch l ->/{
              s/\[ Xml\.block "ul"/heading :: List.flatten (List.map aux t)/
              /Xml\.block "li"/d
              /^      \]$/d
            }' lib/export/html.ml

            # Patch CLI config for document mode
            substituteInPlace bin/main.ml #\
              --replace-fail 'toc = true' 'toc = false' \
              --replace-fail 'parse_outline_only = true' 'parse_outline_only = false' \
              --replace-fail 'heading_number = true' 'heading_number = false' \
              --replace-fail 'heading_to_list = true' 'heading_to_list = false'
          '';
          propagatedBuildInputs = with ocamlPkgs; [
            angstrom
            xmlm
            bigstringaf
            ppx_deriving_yojson
            yojson
            uri
            cmdliner
            lwt
          ];
        };

        # Site generator: OCaml tool that converts org → HTML + RSS
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
            #ocamlPkgs.mldoc
          ];
          buildPhase = "dune build";
          installPhase = ''
            mkdir -p $out/bin
            cp _build/default/main.exe $out/bin/site-generator
          '';
        };

        # Build static site: convert org files to HTML + RSS
        htdocs =
          pkgs.runCommand "mirage-site-htdocs"
            {
              nativeBuildInputs = [
                mldoc
                generator
              ];
            }
            ''
              mkdir -p $out
              site-generator mldoc ${./content} $out ${./templates} ${./static}
            '';

        # Compose source tree with generated htdocs (exclude generator)
        src = pkgs.runCommand "mirage-site-src" { } ''
          cp -r ${./.} $out
          chmod -R u+w $out
          rm -rf $out/htdocs $out/generator $out/templates $out/static
          cp -r ${htdocs} $out/htdocs
        '';

        mirage-nix = hillingar.lib.${system};
        inherit (mirage-nix) mkUnikernelPackages;
      in
      {
        packages =
          (mkUnikernelPackages {
            unikernelName = "mirage-site";
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
          } src)
          // {
            inherit htdocs mldoc generator;
          };

        defaultPackage = self.packages.${system}.unix;
      }
    );
}
