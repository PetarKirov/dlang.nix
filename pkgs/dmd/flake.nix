{
  inputs = {
    dmd = {
      url = github:dlang/dmd;
      flake = false;
    };
    druntime = {
      url = github:dlang/druntime;
      flake = false;
    };
    phobos = {
      url = github:dlang/phobos;
      flake = false;
    };
    tools = {
      url = github:dlang/tools;
      flake = false;
    };
    primary.follows = "dmd";
  };
  outputs = {...}: let
    versionBetween = after: before: version:
      ((builtins.compareVersions version after) >= 0)
      && ((builtins.compareVersions version before) < 0);
  in {
    isVersionSupported = version: versionBetween "2.098.1" "2.102.2" version;
  };
}
