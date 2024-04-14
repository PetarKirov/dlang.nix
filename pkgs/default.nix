{
  inputs,
  lib,
  ...
}: let
  inherit (lib) optionalAttrs;
in {
  imports = [inputs.flake-parts.flakeModules.easyOverlay];

  perSystem = {
    self',
    pkgs,
    ...
  }: let
    inherit
      (import ../lib/version-catalog.nix {inherit lib pkgs;})
      genPkgVersions
      ;
    buildDubPackage = pkgs.callPackage ./build-dub-package {
      dub = self'.packages.dub;
      ldc = self'.packages.ldc;
    };
  in {
    overlayAttrs = self'.packages;
    legacyPackages =
      {}
      // (genPkgVersions "dmd").hierarchical
      // (genPkgVersions "ldc").hierarchical
      // (genPkgVersions "dub").hierarchical;

    packages =
      optionalAttrs pkgs.stdenv.isLinux rec {
        dscanner = pkgs.callPackage ./dscanner {
          inherit buildDubPackage;
        };
        serve-d = pkgs.callPackage ./serve-d {
          inherit buildDubPackage;
        };
        dlangide = pkgs.callPackage ./dlangide {
          inherit buildDubPackage;
        };
        tsv-utils = pkgs.callPackage ./examples/tsv-utils {
          dub = self'.packages.dub;
          dmd = self'.packages.dmd;
        };
        inochi2d = pkgs.callPackage ./examples/inochi2d {
          inherit buildDubPackage;
        };
        graphqld = pkgs.callPackage ./examples/graphqld {
          inherit buildDubPackage;
        };
        dubproxy = pkgs.callPackage ./examples/dubproxy {
          inherit buildDubPackage;
        };
        faked = pkgs.callPackage ./examples/faked {
          inherit buildDubPackage;
        };
        juliad = pkgs.callPackage ./examples/juliad {
          inherit buildDubPackage;
        };
        libbetterc = pkgs.callPackage ./examples/libbetterc {
          inherit buildDubPackage;
        };
        symmetry-gelf = pkgs.callPackage ./examples/symmetry-gelf {
          inherit buildDubPackage;
        };
        xlsxreader = pkgs.callPackage ./examples/xlsxreader {
          inherit buildDubPackage;
        };
        mir-algorithm = pkgs.callPackage ./examples/mir-algorithm {
          inherit buildDubPackage;
        };
        mir-optim = pkgs.callPackage ./examples/mir-optim {
          inherit buildDubPackage;
        };
        dpp = pkgs.callPackage ./examples/dpp {
          inherit buildDubPackage;
        };
        lubeck = pkgs.callPackage ./examples/lubeck {
          inherit buildDubPackage;
        };
        dust-mite = pkgs.callPackage ./examples/dust-mite {
          inherit buildDubPackage;
        };
        concurrency = pkgs.callPackage ./examples/concurrency {
          inherit buildDubPackage;
        };
        arsd = pkgs.callPackage ./examples/arsd {
          inherit buildDubPackage;
        };
      }
      // rec {
        ldc-binary = self'.packages."ldc-binary-1_34_0";
        ldc = self'.packages."ldc-1_30_0";

        dub = self'.packages."dub-1_31_0";
      }
      // (genPkgVersions "ldc").flattened "binary"
      // (genPkgVersions "ldc").flattened "source"
      // (genPkgVersions "dub").flattened "source"
      // optionalAttrs pkgs.hostPlatform.isx86 (
        {
          dmd-bootstrap = self'.packages."dmd-binary-2_098_0";
          dmd = self'.packages."dmd-2_105_2";
        }
        // (genPkgVersions "dmd").flattened "binary"
        // (genPkgVersions "dmd").flattened "source"
      );
  };
}
