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
    flake-utils.lib.eachDefaultSystem (system: {
      packages = dreamlog.lib.${system}.mkDreamlog {
        src = ./.;
      };

      defaultPackage = self.packages.${system}.unix;
    });
}
