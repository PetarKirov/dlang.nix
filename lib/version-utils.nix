{ ... }:
{
  versionBetween =
    after: before: version:
    ((builtins.compareVersions version after) >= 0) && ((builtins.compareVersions version before) < 0);
}
