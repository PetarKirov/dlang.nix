{ ... }:
# SemVer-aware version helpers shared across the package definitions.
rec {
  # after <= version < before
  versionBetween =
    after: before: version:
    ((builtins.compareVersions version after) >= 0) && ((builtins.compareVersions version before) < 0);

  # after <= version <= before
  versionBetweenInclusive =
    after: before: version:
    ((builtins.compareVersions version after) >= 0) && ((builtins.compareVersions version before) <= 0);

  # Version strings sorted ascending by precedence.
  sortVersions = builtins.sort (a: b: (builtins.compareVersions a b) < 0);

  # The newest version string in a non-empty list.
  latestVersion =
    versions:
    let
      sorted = sortVersions versions;
    in
    builtins.elemAt sorted (builtins.length sorted - 1);
}
