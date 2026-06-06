{ inputs, lib, ... }:
let
  inherit (lib) optionalAttrs;
in
{
  imports = [ inputs.flake-parts.flakeModules.easyOverlay ];

  perSystem =
    { self', pkgs, ... }:
    let
      inherit (import ../lib/version-catalog.nix { inherit lib pkgs self'; }) genPkgVersions;
    in
    {
      overlayAttrs = self'.packages;
      legacyPackages =
        { }
        // (genPkgVersions "dmd").hierarchical
        // (genPkgVersions "ldc").hierarchical
        // (genPkgVersions "dub").hierarchical;

      packages =
        {
          # NOTE: This is only the default. The bootstrap compiler in the
          # version catalog will override this.
          ldc-bootstrap = self'.packages."ldc-binary-1_25_0";
          ldc = self'.packages."ldc-1_30_0";

          # DUB is released alongside DMD. When DMD 2.112.0 shipped, upstream
          # appears to have forgotten to bump DUB from 1.42.0-beta.1 to the
          # final 1.42.0 tag, so the newest released DUB is still this beta.
          # Switch to "dub-1_42_0" once upstream tags the stable release.
          dub = self'.packages."dub-1_42_0-beta_1";
        }
        // (genPkgVersions "ldc").flattened "binary"
        // (genPkgVersions "ldc").flattened "source"
        // (genPkgVersions "dub").flattened "source"
        // optionalAttrs pkgs.hostPlatform.isx86 (
          {
            dmd-bootstrap = self'.packages."dmd-binary-2_098_0";
            dmd = self'.packages."dmd-2_112_0";
          }
          // (genPkgVersions "dmd").flattened "binary"
          // (genPkgVersions "dmd").flattened "source"
        );
    };
}
