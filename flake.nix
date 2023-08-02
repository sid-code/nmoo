{
  description = "NMOO";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    supportedSystems = ["x86_64-linux"];
    forAllSystems = f:
      nixpkgs.lib.genAttrs supportedSystems (system:
        f system (import nixpkgs {
          inherit system;
          overlays = [
            (self: super: {
              nim-unwrapped = super.nim-unwrapped.overrideAttrs (o:
                o
                // rec {
                  version = "2.0.0";
                  src = super.fetchurl {
                    url = "https://nim-lang.org/download/nim-${version}.tar.xz";
                    hash = "sha256-vWEB2EADb7eOk6ad9s8/n9DCHNdUtpX/hKO0rdjtCvc=";
                  };
                });
            })
          ];
        }));
  in {
    devShells = forAllSystems (system: pkgs: {
      default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [nim nimlsp libxcrypt watchexec];
      };
    });
  };
}
