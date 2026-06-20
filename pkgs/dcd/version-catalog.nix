lib: rec {
  supportedVersions = {
    source = builtins.fromJSON (builtins.readFile ./supported-source-versions.json);
  };

  getBinaryVersion = null; # unsupported

  getSourceVersion =
    _ourPkgs: version:
    assert builtins.hasAttr version supportedVersions.source;
    let
      componentHashes = supportedVersions.source."${version}";
    in
    import ./default.nix (
      {
        inherit version;
        srcSha256 = componentHashes.src;
      }
      // lib.optionalAttrs (componentHashes ? rev) { inherit (componentHashes) rev; }
    );
}
