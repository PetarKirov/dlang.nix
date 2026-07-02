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

  # `dub test` pulls test-only deps not in the lock; keep checks off for now.
  defaults = {
    build = true;
    check = false;
    skippedTests = [ ];
  };

  # Per-version overrides, merged into every system's entry.
  overrides = {
    # 0.13.6 no longer compiles with a modern LDC/Phobos (std.logger
    # `fatalHandler` shared-overload error in src/dcd/server/main.d).
    "0.13.6" = {
      build = false;
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
