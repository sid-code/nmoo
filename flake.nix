{
  description = "NMOO";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nim2-nixpkgs.url = "github:ehmry/nixpkgs/nim";
  };

  outputs = {
    self,
    nixpkgs,
    nim2-nixpkgs,
    ...
  }: let
    supportedSystems = ["x86_64-linux"];
    nim2Overlay = system: self: super: {
      nim = nim2-nixpkgs.legacyPackages.${system}.nim2;
    };
    forAllSystems = f:
      nixpkgs.lib.genAttrs supportedSystems (system:
        f system (import nixpkgs {
          inherit system;
          overlays = [(nim2Overlay system)];
        }));
  in {
    devShells = forAllSystems (system: pkgs: {
      default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          nim
          nimble-unwrapped
          nimlsp
          libxcrypt
          watchexec
        ];
      };
    });
  };
}
