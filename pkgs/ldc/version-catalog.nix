rec {
  supportedVersions = {
    source = builtins.fromJSON (
      builtins.readFile ./supported-source-versions.json
    );

    binary = builtins.fromJSON (
      builtins.readFile ./supported-binary-versions.json
    );
  };

  getSourceVersion = version:
    assert builtins.hasAttr version supportedVersions.source; let
      componentHashes = supportedVersions.source."${version}";
    in
      import ./generic.nix {
        inherit version;
        sha256 = componentHashes.src;
      };

  getBinaryVersion = version:
    assert builtins.hasAttr version supportedVersions.binary; let
      componentHashes = supportedVersions.binary."${version}";
    in
      import ./binary.nix {
        inherit version;
        hashes = componentHashes;
      };
}
