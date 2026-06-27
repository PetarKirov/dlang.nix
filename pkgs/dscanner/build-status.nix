{ lib }:
let
  inherit (lib) listToAttrs nameValuePair recursiveUpdate;

  versions = builtins.attrNames (lib.importJSON ./supported-source-versions.json);

  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  # `dub test` works for dscanner (as in nixpkgs); enable checks by default.
  defaults = {
    build = true;
    check = true;
    skippedTests = [ ];
  };

  # Per-version overrides, merged into every system's entry.
  overrides = {
    # 0.11.1's unittests fail in the sandbox ("Could not locate object.d");
    # the dscanner binary itself still builds fine.
    "0.11.1" = {
      check = false;
    };
  };

  base = listToAttrs (
    map (
      version: nameValuePair version (listToAttrs (map (system: nameValuePair system defaults) systems))
    ) versions
  );

  expanded = lib.mapAttrs (
    _version: ov: listToAttrs (map (system: nameValuePair system ov) systems)
  ) overrides;
in
recursiveUpdate base expanded
