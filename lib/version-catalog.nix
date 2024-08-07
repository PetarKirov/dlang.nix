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
  inherit (lib) nameValuePair pipe optional;

  inherit (pkgs) callPackage;
  extraPkgs = {
    hostDCompiler = self'.packages.ldc-bootstrap;
    inherit (pkgs.darwin.apple_sdk.frameworks) Foundation;
  };

  system = pkgs.hostPlatform.system;
  filterBySystem = pkgs: lib.filterAttrs (_name: pkg: builtins.elem system pkg.meta.platforms) pkgs;
in
{
  genPkgVersions =
    pkgName:
    let
      mod = ../pkgs/${pkgName}/version-catalog.nix;
      inherit (import mod) supportedVersions getSourceVersion getBinaryVersion;

      supportedTypes =
        (optional (getBinaryVersion != null) "binary") ++ (optional (getSourceVersion != null) "source");

      sanitizeVersion = version: builtins.replaceStrings [ "." ] [ "_" ] version;

      getVersion = type: if type == "source" then getSourceVersion else getBinaryVersion;
    in
    {
      flattened =
        type:
        let
          nameSuffix = if type == "binary" then "-binary" else "";
        in
        pipe (attrNames supportedVersions."${type}") [
          (map (
            version:
            nameValuePair "${pkgName}${nameSuffix}-${sanitizeVersion version}" (
              callPackage (getVersion type version) extraPkgs
            )
          ))
          listToAttrs
          filterBySystem
        ];

      hierarchical = {
        "${pkgName}" = pipe supportedTypes [
          (map (
            type:
            nameValuePair type (
              mapAttrs (version: _: (callPackage (getVersion type version) extraPkgs)) supportedVersions."${type}"
            )
          ))
          listToAttrs
          filterBySystem
        ];
      };
    };
}
