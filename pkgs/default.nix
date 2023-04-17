{inputs, ...}: {
  imports = [inputs.flake-parts.flakeModules.easyOverlay];

  perSystem = {
    self',
    pkgs,
    ...
  }: let
    inherit (pkgs) callPackage;
    darwinPkgs = {
      inherit (pkgs.darwin.apple_sdk.frameworks) Foundation;
    };
  in {
    overlayAttrs = self'.packages;
    packages = {
      dmd = callPackage ./dmd ({} // darwinPkgs);

      ldc = callPackage ./ldc {};

      dub = callPackage ./dub {};
    };
  };
}
