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
  outputs = {...}: {
  };
}
