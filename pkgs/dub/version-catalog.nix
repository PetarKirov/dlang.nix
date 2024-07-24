lib: rec {
  supportedVersions = {
    source = builtins.fromJSON (builtins.readFile ./supported-source-versions.json);
  };

  getBinaryVersion = null; # unsupported

  getSourceVersion =
    pkgs: version:
    assert builtins.hasAttr version supportedVersions.source;
    let
      componentHashes = supportedVersions.source."${version}";
    in
    import ./default.nix {
      inherit version;
      dubSha256 = componentHashes.dub;
    };
}
