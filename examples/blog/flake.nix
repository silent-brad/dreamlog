{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    #dreamlog.url = "github:silent-brad/dreamlog";
    dreamlog.url = "path:../..";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      dreamlog,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        result = dreamlog.lib.${system}.mkDreamlog {
          src = ./.;
        };
      in
      {
        packages = result.packages // {
          site = result.site;
        };

        defaultPackage = self.packages.${system}.unix;
      }
    );
}
