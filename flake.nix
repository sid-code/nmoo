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
        { pkgs, ... }: {
          default = pkgs.buildNimPackage {
            pname = "nmoo";
            version = "0.1.0";
            src = ./.;
            lockFile = ./nimble.lock;

            nativeBuildInputs = [ pkgs.libxcrypt ];
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
            ];
          };
        }
      );
    };
}
