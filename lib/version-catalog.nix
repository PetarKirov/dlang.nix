{
  lib,
  pkgs,
  self',
  ...
}:
let
  inherit (builtins)
    attrNames
    listToAttrs
    map
    mapAttrs
    ;
  inherit (lib)
    nameValuePair
    pipe
    optional
    concatMap
    mapAttrsToList
    ;

  inherit (pkgs) callPackage;

  callWithExtras =
    package:
    let
      result' = callPackage package {
        hostDCompiler = result'.hostDCompiler or self'.packages.ldc-bootstrap;
        inherit (pkgs.darwin.apple_sdk.frameworks) Foundation;
      };
    in
    result';

  system = pkgs.hostPlatform.system;
  filterBySystem = pkgs: lib.filterAttrs (_name: pkg: builtins.elem system pkg.meta.platforms) pkgs;
in
{
  genPkgVersions =
    pkgName:
    let
      mod = ../pkgs/${pkgName}/version-catalog.nix;
      inherit (import mod lib) supportedVersions getSourceVersion getBinaryVersion;

      supportedTypes =
        (optional (getBinaryVersion != null) "binary") ++ (optional (getSourceVersion != null) "source");

      sanitizeVersion = version: builtins.replaceStrings [ "." ] [ "_" ] version;

      getVersion =
        type: if type == "source" then getSourceVersion self'.packages else getBinaryVersion self'.packages;
    in
    {
      flattened =
        type:
        let
          nameSuffix = if type == "binary" then "-binary" else "";
        in
        pipe (attrNames supportedVersions."${type}") [
          (concatMap (
            version:
            let
              drv = callWithExtras (getVersion type version);
              sv = sanitizeVersion version;
              # Source builds expose sub-derivations (untested build + one per
              # test suite) via passthru.stages; lift each to a top-level package
              # named `${pkgName}-${stage}-${version}`. Binary builds have none.
              stages = drv.passthru.stages or { };
            in
            [ (nameValuePair "${pkgName}${nameSuffix}-${sv}" drv) ]
            ++ mapAttrsToList (
              stageName: stageDrv: nameValuePair "${pkgName}-${stageName}-${sv}" stageDrv
            ) stages
          ))
          listToAttrs
          filterBySystem
        ];

      hierarchical = {
        "${pkgName}" = pipe supportedTypes [
          (map (
            type:
            nameValuePair type (
              mapAttrs (version: _: callWithExtras (getVersion type version)) supportedVersions."${type}"
            )
          ))
          listToAttrs
          filterBySystem
        ];
      };
    };
}
