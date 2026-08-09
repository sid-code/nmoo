{
  description = "NMOO";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nim-src = {
      url = "github:nim-lang/Nim/devel";
      flake = false;
    };
    nim-csources = {
      url = "github:nim-lang/csources_v3";
      flake = false;
    };
    nim-checksums = {
      url = "github:nim-lang/checksums";
      flake = false;
    };
    nimony = {
      url = "github:nim-lang/nimony";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nim-src,
      nim-checksums,
      nim-csources,
      nimony,
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
              overlays = [
                (self: super: {
                  nim-devel =
                    (super.nim.override {
                      nim-unwrapped = super.nim-unwrapped.overrideAttrs (o: {
                        version = "devel";
                        src = nim-src;
                        configurePhase =
                          let
                            bootstrapCompiler = super.stdenv.mkDerivation {
                              pname = "nim-bootstrap";
                              version = "3";
                              src = nim-csources;
                              installPhase = ''
                                mkdir -p $out/bin
                                install -m 755 bin/nim $out/bin/nim
                              '';
                            };
                            niftools = super.stdenv.mkDerivation {
                              pname = "niftools";
                              version = "3";
                              src = nimony;
                              # TODO; find a way to use bootstrap compiler
                              buildInputs = [ super.nim ];
                              buildPhase = ''
                                nim c -o:nifler --nimcache:nimcache -d:release --noNimblePath --skipUserCfg --skipParentCfg src/nifler/nifler.nim
                                nim c -o:nifmake --nimcache:nimcache -d:release --noNimblePath --skipUserCfg --skipParentCfg src/nifmake/nifmake.nim
                              '';
                              installPhase = ''
                                runHook preInstall
                                mkdir -p $out/bin
                                install -m 755 nifler $out/bin/nifler
                                install -m 755 nifmake $out/bin/nifmake
                                runHook postInstall
                              '';
                            };
                          in
                          ''
                            runHook preConfigure
                            mkdir dist
                            cp ${bootstrapCompiler}/bin/nim bin/
                            cp -r ${nim-checksums} dist/checksums
                            cp -r ${nimony} dist/nimony
                            cp ${niftools}/bin/nifler bin/nifler
                            cp ${niftools}/bin/nifmake bin/nifmake
                            ls bin
                            echo 'define:nixbuild' >> config/nim.cfg
                            echo 'nimcache:nimcache' >> config/nim.cfg
                            runHook postConfigure
                          '';
                        installPhase = ''
                          ./koch geninstall
                          ${o.installPhase}
                        '';
                      });
                    }).overrideAttrs
                      (o: {
                        version = "devel";
                        unpackPhase = ''
                          runHook preUnpack
                          mkdir nim-$version
                          cp -r ${self.nim-unwrapped}/nim/config nim-$version/config
                          chmod +w -R nim-$version
                          cd nim-$version
                          runHook postUnpack
                        '';
                      });
                })
              ];
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
              nim-devel
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
