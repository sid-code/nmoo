{
  description = "NMOO";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            inherit system;
            pkgs = import nixpkgs {
              inherit system;
            };
          }
        );
    in
    {
      packages = forAllSystems (
        { pkgs, ... }:
        let
          fs = pkgs.lib.fileset;
        in
        {
          default = pkgs.buildNimPackage {
            pname = "nmoo";
            version = "0.1.0";
            src = fs.toSource {
              root = ./.;
              fileset = fs.unions [
                ./nmoo.nimble
                ./src
                ./config.nims
              ];
            };
            nimFlags = [
              "-d:release"
              "-d:danger"
            ];
            lockFile = ./lock.json;
            buildInputs = [ pkgs.libxcrypt ];
            nativeBuildInputs = [ pkgs.pkg-config ];
          };
        }
      );
      devShells = forAllSystems (
        { pkgs, ... }: {
          default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              nim
              nimble
              nimlangserver
              libxcrypt
              watchexec
              gdb
              valgrind
            ];
          };
        }
      );
    };
}
